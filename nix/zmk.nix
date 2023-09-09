{ stdenvNoCC, lib, buildPackages
, cmake, ninja, dtc, gcc-arm-embedded
, zephyr
, board ? "glove80_lh"
, shield ? null
, keymap ? null
, kconfig ? null
}:


let
  # from zephyr/scripts/requirements-base.txt
  packageOverrides = pyself: pysuper: {
    can = pysuper.can.overrideAttrs (_: {
      # horribly flaky test suite full of assertions about timing.
      # >       assert 0.1 <= took < inc(0.3)
      # E       assert 0.31151700019836426 < 0.3
      # E        +  where 0.3 = inc(0.3)
      doCheck = false;
      doInstallCheck = false;
    });
  };

  python = (buildPackages.python3.override { inherit packageOverrides; }).withPackages (ps: with ps; [
    pyelftools
    pyyaml
    packaging
    progress
    anytree
    intelhex
    pykwalify
  ]);

  # Prune the large gcc-arm-embedded package to include just the architectures
  # that we're building for.
  gcc-arm-embedded-pruned =
    let
      src = gcc-arm-embedded;
      architectures = ["v7e-m+fp"];
      architecturePrefixes = builtins.map (x: toString src + "/" + x) [
        "arm-none-eabi/lib/thumb/"
        "arm-none-eabi/lib/arm/"
        "lib/gcc/arm-none-eabi/${src.version}/thumb/"
      ];
      prunedPaths = builtins.map (x: toString src + "/" + x) [
        "share/doc"
        "share/info"
        "share/man"
      ];
    in
    lib.cleanSourceWith {
      name = "gcc-arm-embedded-pruned";
      inherit src;
      filter = (
        path: type:
        let
          prunePath = builtins.elem path prunedPaths;
          matchingArchPrefix = lib.findFirst (p: lib.hasPrefix p path) null architecturePrefixes;
        in
        if prunePath then
          builtins.trace (path + ": pruned") false
        else if !isNull matchingArchPrefix then
          let relPath = lib.removePrefix matchingArchPrefix path;
              matchesArchitecture = builtins.any (arch: lib.hasPrefix arch relPath) architectures;
          in builtins.trace (path + ": arch retained " + lib.boolToString matchesArchitecture) matchesArchitecture
        else true
      );
    };

  requiredZephyrModules = [
    "cmsis" "hal_nordic" "tinycrypt" "littlefs"
  ];

  zephyrModuleDeps = builtins.filter (x: builtins.elem x.name requiredZephyrModules) zephyr.modules;
in

stdenvNoCC.mkDerivation {
  name = "zmk_${board}";

  sourceRoot = "source/app";

  src = builtins.path {
    name = "source";
    path = ./..;
    filter = path: type:
      let relPath = lib.removePrefix (toString ./.. + "/") (toString path);
      in (lib.cleanSourceFilter path type) && ! (
        # Meta files
        relPath == "nix" || lib.hasSuffix ".nix" path ||
        # Transient state
        relPath == "build" || relPath == ".west" ||
        # Fetched by west
        relPath == "modules" || relPath == "tools" || relPath == "zephyr" ||
        # Not part of ZMK
        relPath == "lambda" || relPath == ".github" ||
        # Not needed to build
        relPath == "test" || relPath == "app/tests" || relPath == "docs"
      );
    };

  preConfigure = ''
    cmakeFlagsArray+=("-DUSER_CACHE_DIR=$TEMPDIR/.cache")
  '';

  cmakeFlags = [
    # "-DZephyrBuildConfiguration_ROOT=${zephyr}/zephyr"
    # TODO: is this required? if not, why not?
    # "-DZEPHYR_BASE=${zephyr}/zephyr"
    "-DBOARD_ROOT=."
    "-DBOARD=${board}"
    "-DZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb"
    "-DGNUARMEMB_TOOLCHAIN_PATH=${gcc-arm-embedded-pruned}"
    # TODO: maybe just use a cross environment for this gcc
    "-DCMAKE_C_COMPILER=${gcc-arm-embedded-pruned}/bin/arm-none-eabi-gcc"
    "-DCMAKE_CXX_COMPILER=${gcc-arm-embedded-pruned}/bin/arm-none-eabi-g++"
    "-DCMAKE_AR=${gcc-arm-embedded-pruned}/bin/arm-none-eabi-ar"
    "-DCMAKE_RANLIB=${gcc-arm-embedded-pruned}/bin/arm-none-eabi-ranlib"
    "-DZEPHYR_MODULES=${lib.concatStringsSep ";" zephyrModuleDeps}"
  ] ++
  (lib.optional (shield != null) "-DSHIELD=${shield}") ++
  (lib.optional (keymap != null) "-DKEYMAP_FILE=${keymap}") ++
  (lib.optional (kconfig != null) "-DCONF_FILE=${kconfig}");

  nativeBuildInputs = [ cmake ninja python dtc ];
  buildInputs = [ zephyr ];

  installPhase = ''
    mkdir $out
    cp zephyr/zmk.{uf2,hex,bin,elf} $out
  '';

  passthru = { inherit zephyrModuleDeps; };
}
