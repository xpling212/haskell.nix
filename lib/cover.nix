{ stdenv, lib, haskellLib, pkgs }:

{ name, version, library, tests }:

let
  buildWithCoverage = builtins.map (d: d.covered);
  runCheck = builtins.map (d: haskellLib.check d);

  libraryCovered    = library.covered;
  testsWithCoverage = buildWithCoverage tests;
  checks            = runCheck testsWithCoverage;

  identifier = name + "-" + version;

in stdenv.mkDerivation {
  name = (identifier + "-coverage-report");

  phases = ["buildPhase"];

  buildInputs = (with pkgs; [ ghc cq jq ]);

  buildPhase = ''
    findMixDir() {
      find $1 -iwholename "*/hpc/vanilla/mix" -exec find {} -maxdepth 1 -type d -iwholename "*/mix/*" \; -quit
    }

    findCabalFile() {
      find $1 -iname "*.cabal" -print -quit
    }

    mkdir -p $out/share/hpc/mix/${identifier}
    mkdir -p $out/share/hpc/tix/${identifier}

    local src=${libraryCovered.src.outPath}

    hpcMarkupCmdBase=("hpc" "markup" "--srcdir=$src")
    for drv in ${lib.concatStringsSep " " ([ libraryCovered ] ++ testsWithCoverage)}; do
      # Copy over mix files
      local mixDir=$(findMixDir $drv)
      echo "MIXDIR IS: $mixDir"
      cp -R $mixDir $out/share/hpc/mix/

      hpcMarkupCmdBase+=("--hpcdir=$mixDir")
    done

    # Exclude test modules from tix file
    excludedModules=('"Main"')
    # Exclude test modules
    local cabalFile=$(findCabalFile $src)
    for module in $(cq $cabalFile testModules | jq ".[]"); do
      excludedModules+=("$module")
    done
    echo "''${excludedModules[@]}"

    hpcSumCmdBase=("hpc" "sum" "--union" "--output=$out/share/hpc/tix/${identifier}/${identifier}.tix")
    for exclude in ''${excludedModules[@]}; do
      hpcSumCmdBase+=("--exclude=$exclude")
      hpcMarkupCmdBase+=("--exclude=$exclude")
    done

    hpcMarkupCmdAll=("''${hpcMarkupCmdBase[@]}" "--destdir=$out/share/hpc/html/${identifier}")

    hpcSumCmd=("''${hpcSumCmdBase[@]}")
    ${lib.concatStringsSep "\n" (builtins.map (check: ''
      local hpcMarkupCmdEachTest=("''${hpcMarkupCmdBase[@]}" "--destdir=$out/share/hpc/html/${check.exeName}")

      pushd ${check}/share/hpc/tix

      tixFileRel="$(find . -iwholename "*.tix" -type f -print -quit)"
      echo "TIXFILEREL: $tixFileRel"

      # Output tix file as-is with suffix
      mkdir -p $out/share/hpc/tix/$(dirname $tixFileRel)
      cp $tixFileRel $out/share/hpc/tix/$tixFileRel
      
      # Output tix file with test modules excluded
      hpcSumCmd+=("$out/share/hpc/tix/$tixFileRel")

      hpcMarkupCmdAll+=("$out/share/hpc/tix/$tixFileRel")
      hpcMarkupCmdEachTest+=("$out/share/hpc/tix/$tixFileRel")

      echo "''${hpcMarkupCmdEachTest[@]}"
      eval "''${hpcMarkupCmdEachTest[@]}"

      popd
    '') checks)
    }

    echo "''${hpcSumCmd[@]}"
    eval "''${hpcSumCmd[@]}"

    echo "''${hpcMarkupCmdAll[@]}"
    eval "''${hpcMarkupCmdAll[@]}"

  '';
}
