{ stdenv, lib, fetchgit }:
let
  manifestJSON = builtins.fromJSON (builtins.readFile ./manifest.json);

  # To reduce closure size, prune paths that are unnecessary for building zmk
  # from zephyr and its dependencies.
  prunedPaths = {
    zephyr = ["tests" "doc"];
    lvgl   = ["demos" "docs" "examples" "scripts" "tests"];
  };

  projects = lib.listToAttrs (lib.forEach manifestJSON ({ name, revision, url, sha256, ... }@args: (
    let
      src = fetchgit {
        name = "${name}-orig";
        inherit url sha256;
        rev = revision;
      };
      filteredSrc = lib.cleanSourceWith {
        inherit name src;
        filter = path: type:
          let
            relPath = lib.removePrefix (toString src + "/") (toString path);
          in !builtins.elem (builtins.trace relPath relPath) (prunedPaths.${name} or []);
      };
    in
    lib.nameValuePair name {
      path = args.path or name;
      src = filteredSrc;
    })
  ));
in

# Zephyr with no modules, from the frozen manifest.
# For now the modules are passed through as passthru
stdenv.mkDerivation {
  name = "zephyr";
  src = projects.zephyr.src;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/zephyr
    mv * $out/zephyr
  '';

  passthru = {
    modules = map (p: p.src) (lib.attrValues (removeAttrs projects ["zephyr"]));
  };
}
