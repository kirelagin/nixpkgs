{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.buildkite-agents;

  mkHookOption = { name, description, example ? null }: {
    inherit name;
    value = mkOption {
      default = null;
      inherit description;
      type = types.nullOr types.lines;
    } // (if example == null then {} else { inherit example; });
  };
  mkHookOptions = hooks: listToAttrs (map mkHookOption hooks);

  hooksDir = cfg: let
    mkHookEntry = name: value: ''
      cat > $out/${name} <<'EOF'
      #! ${pkgs.runtimeShell}
      set -e
      ${value}
      EOF
      chmod 755 $out/${name}
    '';
  in pkgs.runCommand "buildkite-agent-hooks" { preferLocalBuild = true; } ''
    mkdir $out
    ${concatStringsSep "\n" (mapAttrsToList mkHookEntry (filterAttrs (n: v: v != null) cfg.hooks))}
  '';

  buildkiteOptions =  { name ? "", config, ... }:
  let
    fullName = if name == "" then "buildkite-agent" else "buildkite-agent-${name}";
  in
  { options = {
      enable = mkOption {
        default = true;
        type = types.bool;
        description = "Whether to enable this buildkite agent";
      };

      package = mkOption {
        default = pkgs.buildkite-agent;
        defaultText = "pkgs.buildkite-agent";
        description = "Which buildkite-agent derivation to use";
        type = types.package;
      };

      dataDir = mkOption {
        default = "/var/lib/${fullName}";
        description = "The workdir for the agent";
        type = types.str;
      };

      fullName = mkOption {
        readOnly = true;
        default = fullName;
        description = ''
          Full name of the systemd service unit and of the user it runs as.
        '';
      };

      runtimePackages = mkOption {
        default = [ pkgs.bash pkgs.nix ];
        defaultText = "[ pkgs.bash pkgs.nix ]";
        description = "Add programs to the buildkite-agent environment";
        type = types.listOf types.package;
      };

      tokenPath = mkOption {
        type = types.path;
        description = ''
          The token from your Buildkite "Agents" page.

          A run-time path to the token file, which is supposed to be provisioned
          outside of Nix store.
        '';
      };

      name = mkOption {
        type = types.str;
        default = "%hostname-${name}-%n";
        description = ''
          The name of the agent as seen in the buildkite dashboard.
        '';
      };

      tags = mkOption {
        type = let
          commasToAttrs = commas: builtins.foldl'
            (prev: cur: let pair = builtins.split "=" cur; in
                 prev // {"${lib.head pair}" = lib.last pair; })
            {} (lib.remove [] (builtins.split "," commas)); in
          types.coercedTo types.string commasToAttrs (types.attrsOf types.str);
        default = {};
        example = { queue = "default"; docker = "true"; ruby2 = "true"; };
        description = ''
          Meta data for the agent.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        example = "debug=true";
        description = ''
          Extra lines to be added verbatim to the configuration file.
        '';
      };

      extraSetup = mkOption {
        type = types.lines;
        default = "";
        example = "touch $HOME/test";
        description = ''
          Extra commands to execute (as root) while setting up the buildkite dir and config.
          The directory ownership will be fixed up afterwards.
        '';
      };

      sshKeyPath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Private agent SSH key.

          A runtime path to the key file, which is supposed to be provisioned
          outside of Nix store.
        '';
      };

      hooks = mkHookOptions [
        { name = "checkout";
          description = ''
            The `checkout` hook script will replace the default checkout routine of the
            bootstrap.sh script. You can use this hook to do your own SCM checkout
            behaviour
          ''; }
        { name = "command";
          description = ''
            The `command` hook script will replace the default implementation of running
            the build command.
          ''; }
        { name = "environment";
          description = ''
            The `environment` hook will run before all other commands, and can be used
            to set up secrets, data, etc. Anything exported in hooks will be available
            to the build script.

            Note: the contents of this file will be copied to the world-readable
            Nix store.
          '';
          example = ''
            export SECRET_VAR=`head -1 /run/keys/secret`
          ''; }
        { name = "post-artifact";
          description = ''
            The `post-artifact` hook will run just after artifacts are uploaded
          ''; }
        { name = "post-checkout";
          description = ''
            The `post-checkout` hook will run after the bootstrap script has checked out
            your projects source code.
          ''; }
        { name = "post-command";
          description = ''
            The `post-command` hook will run after the bootstrap script has run your
            build commands
          ''; }
        { name = "pre-artifact";
          description = ''
            The `pre-artifact` hook will run just before artifacts are uploaded
          ''; }
        { name = "pre-checkout";
          description = ''
            The `pre-checkout` hook will run just before your projects source code is
            checked out from your SCM provider
          ''; }
        { name = "pre-command";
          description = ''
            The `pre-command` hook will run just before your build command runs
          ''; }
        { name = "pre-exit";
          description = ''
            The `pre-exit` hook will run just before your build job finishes
          ''; }
      ];

      hooksPath = mkOption {
        type = types.path;
        default = hooksDir config;
        defaultText = "generated from services.buildkite-agent.hooks";
        description = ''
          Path to the directory storing the hooks.
          Consider using <option>services.buildkite-agent.hooks.&lt;name&gt;</option>
          instead.
        '';
      };

      shell = mkOption {
        type = types.string;
        default = "${pkgs.bash}/bin/bash -e -c";
        description = ''
          Command that buildkite-agent 3 will execute when it spawns a shell.
        '';
      };
  };
};

  enabledAgents = lib.filterAttrs (n: v: v.enable) cfg;
  mapAgents = function: lib.mkMerge (lib.mapAttrsToList function enabledAgents);
in {
  options.services.buildkite-agents = mkOption {
    type = types.attrsOf (types.submodule buildkiteOptions);
    default = {};
    description = ''
      Attribute set of buildkite agents.

      The attribute key is combined with the hostname and a unique integer to
      create the final agent name. This can be overridden by setting the `name`
      attribute.
    '';
  };

  config.users.users = mapAgents (name: cfg: {
    "${cfg.fullName}" =
      { name = cfg.fullName;
        home = cfg.dataDir;
        createHome = true;
        description = "Buildkite agent user";
        extraGroups = [ "keys" ];
      };
    });

  config.systemd.services = mapAgents (name: cfg: {
    "${cfg.fullName}" =
      { description = "Buildkite Agent";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        path = cfg.runtimePackages ++ [ cfg.package pkgs.coreutils ];
        environment = config.networking.proxy.envVars // {
          HOME = cfg.dataDir;
          NIX_REMOTE = "daemon";
          BUILDKITE_SHELL = cfg.shell;
        };

        ## NB: maximum care is taken so that secrets (ssh keys and the CI token)
        ##     don't end up in the Nix store.
        ## This preStart script runs as root
        preStart = let
          sshDir = "${cfg.dataDir}/.ssh";
          sshKeyPath = toString cfg.sshKeyPath;
          tagStr = lib.concatStringsSep "," (lib.mapAttrsToList (name: value: "${name}=${value}") cfg.tags);
        in
          ''
            ${optionalString (cfg.sshKeyPath != null) ''
              mkdir -m 0700 -p "${sshDir}"
              cp -f "${sshKeyPath}" "${sshDir}/id_rsa"
              chmod 600 "${sshDir}"/id_rsa
            ''}

            cat > "${cfg.dataDir}/buildkite-agent.cfg" <<EOF
            token="$(cat ${toString cfg.tokenPath})"
            name="${cfg.name}"
            tags="${tagStr}"
            build-path="${cfg.dataDir}/builds"
            hooks-path="${cfg.hooksPath}"
            ${cfg.extraConfig}
            EOF
            ${cfg.extraSetup}
            chown -R ${cfg.fullName} ${cfg.dataDir}
          '';

        serviceConfig =
          { ExecStart = "${cfg.package}/bin/buildkite-agent start --config ${cfg.dataDir}/buildkite-agent.cfg";
            User = cfg.fullName;
            RestartSec = 5;
            Restart = "on-failure";
            TimeoutSec = 10;
            # set a long timeout to give buildkite-agent a chance to finish current builds
            TimeoutStopSec = "2 min";
            KillMode = "mixed";
            # run the preStart script as root
            PermissionsStartOnly = true;
          };
      };
  });
  config.assertions = mapAgents (name: cfg: [
      { assertion = cfg.hooksPath == hooksDir cfg || all isNull (attrValues cfg.hooks);
        message = ''
          Options `services.buildkite-agent.hooksPath' and
          `services.buildkite-agent.hooks.<name>' are mutually exclusive.
        '';
      }
  ]);
}
