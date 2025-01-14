args@{ lib, stdenv, clwrapper, baseName, packageName ? baseName, parasites ? [ ]
, buildSystems ? ([ packageName ] ++ parasites), version ? "latest", src
, description, deps, buildInputs ? [ ], meta ? { }, overrides ? (x: { })
, propagatedBuildInputs ? [ ]
, asdFilesToKeep ? [ (builtins.concatStringsSep "" [ packageName ".asd" ]) ] }:
let
  deployConfigScript = ''
    outhash="$out"
    outhash="''${outhash##*/}"
    outhash="''${outhash%%-*}"
    config_script="$out"/lib/common-lisp-settings/${args.baseName}-shell-config.sh
    path_config_script="$out"/lib/common-lisp-settings/${args.baseName}-path-config.sh
    store_translation="$(dirname "$out"):$(dirname "$out")"
    mkdir -p "$(dirname "$config_script")"
    touch "$config_script"
    touch "$path_config_script"
    chmod a+x "$config_script"
    chmod a+x "$path_config_script"
    echo "if test -z \"\''${_''${outhash}_NIX_LISP_CONFIG:-}\"; then export _''${outhash}_NIX_LISP_CONFIG=1; " >> "$config_script"
    echo "export NIX_CFLAGS_COMPILE='$NIX_CFLAGS_COMPILE'\"\''${NIX_CFLAGS_COMPILE:+ \$NIX_CFLAGS_COMPILE}\"" >> "$config_script"
    echo "export NIX_LDFLAGS='$NIX_LDFLAGS'\"\''${NIX_LDFLAGS:+ \$NIX_LDFLAGS}\"" >> "$config_script"
    echo "export NIX_LISP_COMMAND='$NIX_LISP_COMMAND'" >> "$config_script"
    echo "export NIX_LISP_ASDF='$NIX_LISP_ASDF'" >> "$config_script"
    set | grep NIX_CC_WRAPPER_ | sed -e 's@^NIX_CC_WRAPPER@export &@' >> "$config_script"
    echo "export PATH=\"\''${PATH:+\$PATH:}$PATH\"" >> "$config_script"
    echo "echo \"\$ASDF_OUTPUT_TRANSLATIONS\" | grep -E '(^|:)$store_translation(:|\$)' >/dev/null || export ASDF_OUTPUT_TRANSLATIONS=\"\''${ASDF_OUTPUT_TRANSLATIONS:+\$ASDF_OUTPUT_TRANSLATIONS:}\"'$store_translation'" >> "$config_script"
    echo "source '$path_config_script'" >> "$config_script"
    echo "fi" >> "$config_script"
    echo "if test -z \"\''${_''${outhash}_NIX_LISP_PATH_CONFIG:-}\"; then export _''${outhash}_NIX_LISP_PATH_CONFIG=1; " >> "$path_config_script"
    echo "export NIX_LISP_ASDF_PATHS=\"$( ( echo "\''${NIX_LISP_ASDF_PATHS:-}"; echo "$NIX_LISP_ASDF_PATHS"; echo "$out/lib/common-lisp/${args.baseName}" ) | grep . | sort | uniq)\"" >> "$path_config_script"
    test -n "$LD_LIBRARY_PATH" &&
        echo "export LD_LIBRARY_PATH=\"\$LD_LIBRARY_PATH\''${LD_LIBRARY_PATH:+:}\"'$LD_LIBRARY_PATH'" >> "$path_config_script"
    test -n "$NIX_LISP_LD_LIBRARY_PATH" &&
        echo "export NIX_LISP_LD_LIBRARY_PATH=\"\''${NIX_LISP_LD_LIBRARY_PATH:-}\''${NIX_LISP_LD_LIBRARY_PATH:+:}\"'$(echo "$NIX_LISP_LD_LIBRARY_PATH" | tr -d '\n' | tr : '\n' | sort | uniq | tr '\n' ':' | sed -e 's/:$//')'" >> "$path_config_script"
    echo "fi" >> "$path_config_script"
  '';
  deployLaunchScript = ''
    launch_script="$out"/bin/${args.baseName}-lisp-launcher.sh
    mkdir -p "$(dirname "$launch_script")"
    touch "$launch_script"
    chmod a+x "$launch_script"
    echo "#! ${stdenv.shell}" >> "$launch_script"
    echo "source '$config_script'" >> "$launch_script"
    echo "test -n \"\$NIX_LISP_LD_LIBRARY_PATH\" && export LD_LIBRARY_PATH=\"\$NIX_LISP_LD_LIBRARY_PATH\''${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH\"" >> "$launch_script"
    echo '"${clwrapper}/bin/common-lisp.sh" "$@"' >> "$launch_script"
  '';
  moveAsdFiles = ''
    find $out/lib/common-lisp/ -name '*.asd' | while read ASD_FILE; do
      KEEP_THIS_ASD=0
      for ALLOWED_ASD in $asdFilesToKeep; do
        ALLOWED_ASD="/$ALLOWED_ASD"
        ALLOWED_ASD_LENGTH=${"$"}{#ALLOWED_ASD}
        ASD_FILE_LENGTH=${"$"}{#ASD_FILE}
        ASD_FILE_SUFFIX_INDEX=$(expr "$ASD_FILE_LENGTH" - "$ALLOWED_ASD_LENGTH")
        ASD_FILE_SUFFIX_INDEX=$(expr "$ASD_FILE_SUFFIX_INDEX" + 1)
        echo $ALLOWED_ASD $ASD_FILE $ASD_FILE_SUFFIX_INDEX $(expr substr "$ASD_FILE" "$ASD_FILE_SUFFIX_INDEX" "$ASD_FILE_LENGTH")
        if [ "$(expr substr "$ASD_FILE" "$ASD_FILE_SUFFIX_INDEX" "$ASD_FILE_LENGTH")" == "$ALLOWED_ASD" ]; then
          KEEP_THIS_ASD=1
          break
        fi
      done
      if [ "$KEEP_THIS_ASD" == 0 ]; then
        mv "$ASD_FILE"{,.sibling}
      fi
    done
  '';
  basePackage = {
    name = "lisp-${baseName}-${version}";
    inherit src;

    dontBuild = true;

    inherit deployConfigScript deployLaunchScript;
    inherit asdFilesToKeep moveAsdFiles;
    installPhase = ''
      eval "$preInstall"
      mkdir -p "$out"/share/doc/${args.baseName};
      mkdir -p "$out"/lib/common-lisp/${args.baseName};
      cp -r . "$out"/lib/common-lisp/${args.baseName};
      cp -rf doc/* LICENCE LICENSE COPYING README README.html README.md readme.html "$out"/share/doc/${args.baseName} || true
      ${deployConfigScript}
      ${deployLaunchScript}
      ${moveAsdFiles}
      env -i \
      NIX_LISP="$NIX_LISP" \
      NIX_LISP_PRELAUNCH_HOOK='nix_lisp_run_single_form "(progn
            ${
              lib.concatMapStrings (system: ''
                (asdf:compile-system :${system})
                (asdf:load-system :${system})
                (asdf:operate (quote asdf::compile-bundle-op) :${system})
                (ignore-errors (asdf:operate (quote asdf::deploy-asd-op) :${system}))
              '') buildSystems
            }
            )"' \
         "$out/bin/${args.baseName}-lisp-launcher.sh"
      eval "$postInstall"
    '';
    propagatedBuildInputs = (args.deps or [ ])
      ++ [ clwrapper clwrapper.lisp clwrapper.asdf ]
      ++ (args.propagatedBuildInputs or [ ]);
    buildInputs = buildInputs;
    dontStrip = true;

    ASDF_OUTPUT_TRANSLATIONS = "${builtins.storeDir}/:${builtins.storeDir}";

    meta = { inherit description version; } // meta;
  };
  package = basePackage // (overrides basePackage);
in stdenv.mkDerivation package
