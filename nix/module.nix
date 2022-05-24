{ pkgs
, config
, lib
, ...
}:
with lib;

# TODO: debug udev rule doesnt trigger
# TODO: debug mainfeature doesnt work as intended (only the MAIN track being decoded)

let
  cfg = config.phil.arm;

  armpy = pkgs.python3.withPackages (ps: with ps; [
    (buildPythonPackage rec {
      pname = "robobrowser";
      version = "0.5.3";
      propagatedBuildInputs = [ requests werkzeug six beautifulsoup4 tox sphinx nose mock coveralls ];
      src = fetchPypi {
        inherit pname version;
        sha256 = "sha256-MSGayrQcporc6SjlweBKzrukzqvrRHucXkCNezD+6YM=";
      };
      doCheck = false;
    })
    (buildPythonPackage rec {
      pname = "pydvdid";
      version = "1.0";
      src = fetchPypi {
        inherit pname version;
        sha256 = "sha256-EQod1k6CJnzmEvUgylfYvCFHeTXnWIIwMlbR9M0vEws=";
      };
    })
    (buildPythonPackage rec {
      pname = "tinydownload";
      version = "0.1.0";
      format = "wheel";
      propagatedBuildInputs = [ requests beautifulsoup4 ];
      src = fetchPypi {
        inherit pname version format;
        sha256 = "sha256-jdkuzoe7V/GoGtlzzt15q7GxFHh8RhqRaM0AP2QPLy0=";
      };
    })
    markdown
    pycurl
    requests
    urllib3
    xmltodict
    pyudev
    pyyaml
    flask
    flask_wtf
    flask_sqlalchemy
    flask_migrate
    flask-cors
    psutil
    netifaces
    flask_login
    apprise
    bcrypt
    musicbrainzngs
    discid
    prettytable
  ]);

  # just the original repo source
  raw_arm_src = pkgs.fetchFromGitHub {
    repo = "automatic-ripping-machine";
    owner = "automatic-ripping-machine";
    rev = "cf5fbed48613b3711ac35a255bc51dcb69e61a40";
    sha256 = "sha256-P0pRiYv9n4nxNPruLc67RHV8Oo/qA47JiHRcBw2PCIQ=";
  };

  # generate a default config for the ripping process
  default_config = pkgs.runCommandLocal "arm.yaml" {} ''
    substitute ${./arm.yaml} $out                                   \
      --replace @arm_path@ ${raw_arm_src}                           \
      --replace @abcde_config@ ${./abcde.conf}                      \
      --replace @raw_path@ ${cfg.rawPath}                           \
      --replace @transcode_path@ ${cfg.transcodePath}               \
      --replace @completed_path@ ${cfg.completedPath}               \
      --replace @log_path@ ${cfg.logPath}                           \
      --replace @db_file@ ${cfg.dbFile}                             \
      --replace @web_ip@ ${cfg.webIp}                               \
      --replace @web_port@ ${cfg.webPort}                           \
      --replace @handbrake_cmd@ ${pkgs.handbrake}/bin/HandBrakeCLI  \
      --replace @hb_bd_args@ "${cfg.hbBdArgs}"                      \
      --replace @hb_dvd_args@ "${cfg.hbDvdArgs}"
  '';

  # add config to source -> scripts need it
  arm-src = pkgs.runCommandLocal "arm-src" { src = raw_arm_src; } ''
    mkdir -p $out
    cp -r $src/* $out
    cp ${cfg.configFile} $out/arm.yaml
  '';

  # wrap the main ripping process in neat little script
  fullrip = pkgs.writeShellScriptBin "fullrip" ''
    DEVICE=$1
    if [ -d "/dev/$DEVICE" ]; then
      PYTHONPATH=${arm-src}/ ${armpy}/bin/python ${arm-src}/arm/ripper/main.py -d $DEVICE
    else
      echo "please provide a valid device to rip & encode"
      exit
    fi
  '';

  # wrap the provided identifying script
  #arm-core = pkgs.runCommandLocal "udev-test-why" {} ''
    #mkdir -p $out/bin
    #echo "${pkgs.coreutils}/bin/touch /home/maelstroem/WHY2" > $out/bin/test
    #chmod +x $out/bin/test
  #'';
  arm-core = pkgs.runCommandLocal "arm-core.sh" { } ''
    substitute ${./arm_wrapper.sh} $out                       \
      --replace @configFile@ ${cfg.configFile}                \
      --replace @lsdvd@ ${pkgs.lsdvd}/bin/lsdvd               \
      --replace @pythonpath@ ${arm-src}/                      \
      --replace @python@ ${armpy}/bin/python                  \
      --replace @rippermain@ ${arm-src}/arm/ripper/main.py    \
      --replace @binsh@ ${pkgs.bash}/bin/bash                 \
      --replace @su@ ${pkgs.su}/bin/su
    chmod +x $out
  '';
in {
  options.phil.arm = {
    enable = mkOption {
      description = "enable the arm (automatic media ripping) module";
      type = types.bool;
      default = false;
    };

    outputDir = mkOption {
      description = "directory for the output files";
      type = types.str;
    };

    configFile = mkOption {
      description = "config file";
      type = types.path;
      default = default_config;
    };

    dbFile = mkOption {
      description = "db file";
      type = types.str;
      default = "/home/arm/arm.db";
    };

    hbBdArgs = mkOption {
      description = "handbrake bluray args";
      type = types.str;
      #default = "--subtitle scan -F --subtitle-burned --audio-lang-list eng --all-audio";
      default = "--all-subtitles --all-audio";
    };

    hbDvdArgs = mkOption {
      description = "handbrake DVD args";
      type = types.str;
      default = "--subtitle scan -F";
    };

    rawPath = mkOption {
      description = "path for the raw dumps";
      type = types.str;
    };

    transcodePath = mkOption {
      description = "path for the transcoding";
      type = types.str;
    };

    completedPath = mkOption {
      description = "path for the completed transcodes";
      type = types.str;
    };

    logPath = mkOption {
      description = "path for the logs";
      type = types.str;
    };

    webIp = mkOption {
      description = "ip for the web application";
      type = types.str;
      default = "0.0.0.0";
    };

    webPort = mkOption {
      description = "port for the web application";
      type = types.str;
      default = "9091";
    };
  };

  config = mkIf (cfg.enable) {
    boot.kernelModules = [ "sg" ];

    services.udev.extraRules = ''
        ACTION=="change", SUBSYSTEM=="block", KERNEL=="sr0", RUN+="${pkgs.bash}/bin/bash ${arm-core} %k"
    '';

    # needed for script
    fileSystems."/mnt/dev/sr0" = {
      device = "/dev/sr0";
      fsType = "udf,iso9660";
      options = [ "users,noauto,exec,utf8" ];
    };

    # extra system packages
    environment.systemPackages = with pkgs; [
      #libaacs
      #libbluray

      # blurays/dvds
      makemkv
      handbrake

      # cd
      abcde

      # notification daemons
      notify           # discord / telegram
      matrix-commander # matrix

      # for debugging
      fullrip
    ];

    # ui service
    systemd.services.arm-ui = {
      description = "Arm ui service";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = { PYTHONPATH = "${arm-src}/"; };

      serviceConfig = {
        User = "arm";
        Group = "arm";
        Restart = "always";

        ExecStart = "${armpy}/bin/python ${arm-src}/arm/runui.py";
      };
    };

    # user + group for the ui service
    users.extraUsers.arm = {
      isSystemUser = true;
      group = "arm";
      home = "/home/arm";
      createHome = true;
      extraGroups = [ "cdrom" ];
    };
    users.extraGroups.arm = {};
  };
}
