{
  description = "NAHO's portfolio";

  inputs = {
    flakeUtils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    preCommitHooks = {
      inputs = {
        flake-utils.follows = "flakeUtils";
        nixpkgs-stable.follows = "preCommitHooks/nixpkgs";
        nixpkgs.follows = "nixpkgs";
      };

      url = "github:cachix/pre-commit-hooks.nix";
    };
  };

  outputs = {
    self,
    flakeUtils,
    nixpkgs,
    preCommitHooks,
    ...
  }:
    flakeUtils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        checks = {
          preCommitHooks = preCommitHooks.lib.${system}.run {
            hooks = {
              alejandra.enable = true;
              convco.enable = true;
              typos.enable = true;
              yamllint.enable = true;
            };

            settings.alejandra.verbosity = "quiet";
            src = ./.;
          };
        };

        devShells.default = pkgs.mkShell {
          inherit (self.checks.${system}.preCommitHooks) shellHook;
        };

        packages.default = let
          dimension = {
            height = 1440;
            width = 2560;
          };

          name = "version-control-visualization";
        in
          pkgs.stdenv.mkDerivation {
            inherit name;

            buildPhase = let
              imageWidth = toString (
                (pkgs.lib.trivial.max dimension.height dimension.width) / 4
              );
            in ''
              parallel \
                --halt now,fail=1 \
                ' \
                  convert \
                    -background transparent \
                    -resize ${imageWidth}x \
                    {} \
                    {.}.png && \
                    image_optim \
                    {.}.png \
                ' \
                ::: *.svg
            '';

            installPhase = let
              application = pkgs.writeShellApplication {
                inherit name;
                runtimeInputs = with pkgs; [ffmpeg gource parallel];

                text = ''
                  set +o nounset

                  help_message() {
                    printf \
                      '%b\n' \
                      "Usage: $0 -p PATH [OPTIONS]\n" \
                      "Generate version control visualizations in parallel.\n" \
                      "Options:" \
                      "\t-d DIMENSIONS\t\tSet the video dimensions (default: '$DEFAULT_DIMENSIONS')" \
                      "\t-f FPS\t\t\tSet the FPS of the video output (default: '$DEFAULT_FPS')" \
                      "\t-h\t\t\tDisplay this help message" \
                      "\t-o OUTPUT_DIRECTORY\tSet the output directory (default: '$DEFAULT_OUTPUT_DIRECTORY')" \
                      "\t-p PATH\t\t\tAdd a supported version control directory, a log file, or a 'gource' config file, as specified by 'gource', to the batch queue (example: 'path/to/repository')" \
                      >&2
                  }

                  parse_cli_arguments() {
                    while getopts d:f:ho:p: flag; do
                      case "$flag" in
                        d) DIMENSIONS="$OPTARG" ;;
                        f) FPS="$OPTARG" ;;

                        h)
                          help_message
                          exit 0
                          ;;

                        o)
                          if [[ ! -d "$OPTARG" ]]; then
                            printf \
                              '%s\n' \
                              "Invalid output directory: $OPTARG" \
                              >&2

                            help_message
                            exit 2
                          fi

                          OUTPUT_DIRECTORY="$OPTARG"
                          ;;

                        p) PATHS["$OPTARG"]="" ;;

                        *)
                          help_message
                          exit 1
                          ;;
                      esac
                    done

                    if (( ''${#PATHS[@]} == 0 )); then
                      help_message
                      exit 3
                    fi
                  }

                  main() {
                    # https://stackoverflow.com/questions/59895
                    SCRIPT_DIR="$(cd -- "$(dirname -- "''${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
                    readonly SCRIPT_DIR

                    readonly DEFAULT_DIMENSIONS="${toString dimension.width}x${toString dimension.height}"
                    readonly DEFAULT_FPS="60"
                    readonly DEFAULT_OUTPUT_DIRECTORY="."

                    DIMENSIONS="$DEFAULT_DIMENSIONS"
                    FPS="$DEFAULT_FPS"
                    OUTPUT_DIRECTORY="$DEFAULT_OUTPUT_DIRECTORY"

                    declare -A PATHS

                    parse_cli_arguments "$@"

                    readonly DIMENSIONS
                    readonly FPS
                    readonly OUTPUT_DIRECTORY
                    readonly PATHS

                    parallel \
                      --halt now,fail=1 \
                      --will-cite \
                      " \
                        output={1}; \

                        gource \
                          --auto-skip-seconds .01 \
                          --background-colour 1a1b26 \
                          --follow-user NAHO \
                          --hide mouse,progress \
                          --highlight-dirs \
                          --multi-sampling \
                          --seconds-per-day 1 \
                          --stop-at-end \
                          --user-image-dir \"$SCRIPT_DIR/../etc/gource\" \
                          -o - \
                          \"-$DIMENSIONS\" \
                          {1} | \
                          ffmpeg \
                          -y \
                          -r \"$FPS\" \
                          -f image2pipe \
                          -vcodec ppm \
                          -i - \
                          -vcodec libx264 \
                          -preset ultrafast \
                          -pix_fmt yuv420p \
                          -crf 1 \
                          -threads 0 \
                          -bf 0 \
                          \"$OUTPUT_DIRECTORY/\''${output//[^[:alnum:]]/_}.mp4\" \
                      " \
                      ::: "''${!PATHS[@]}"
                  }

                  main "$@"
                '';
              };
            in ''
              mkdir \
                --parent \
                "$out/bin" \
                "$out/etc/gource"

              ln \
                --symbolic \
                "${application}/bin/${application.meta.mainProgram}" \
                "$out/bin"

              mv *.png *.jpg "$out/etc/gource"
            '';

            nativeBuildInputs = with pkgs; [imagemagick image_optim parallel];
            src = version_control_visualization/assets;
          };
      }
    );
}
