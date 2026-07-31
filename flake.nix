{
  description = "rr debugger with software counters support: https://github.com/sidkshatriya/rr.soft";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem =
        {
          self,
          pkgs,
          system,
          ...
        }:
        let
          rr_compiled_with =
            flavor: software_counters_plugin:
            pkgs.rr.overrideAttrs (prev: {
              version = "soft-post5.9.0+builtwith${flavor}";
              src = ./.;
              # Patch was already applied in commit 6251648873b9e1ed23536beebbaa5d6fead3d5be
              patches = [ ];
              nativeBuildInputs = [
                pkgs.ninja
              ]
              ++ prev.nativeBuildInputs;
              buildInputs = [
                pkgs.bzip2
                pkgs.zstd
                pkgs.lz4
                pkgs.snappy
                pkgs.rocksdb
                pkgs.openssl
              ]
              ++ pkgs.lib.optionals (system == "x86_64-linux") [ pkgs.zydis ]
              ++ prev.buildInputs;
              # Removed it by overriding in flake -- seems obsolete
              preConfigure = "";
              cmakeFlags = prev.cmakeFlags ++ [
                "-DSOFTWARE_COUNTERS_PLUGIN=${software_counters_plugin}/lib/libSoftwareCounters.so"
                "-DCMAKE_CXX_STANDARD=20" # rocksdb 10.10.1 requires C++20
                "-GNinja"
              ];
              dontStrip = true;
            });
          libSoftwareCountersGccFor =
            gccStdenvArg:
            gccStdenvArg.mkDerivation {
              pname = "libSoftwareCountersGcc${pkgs.lib.versions.major gccStdenvArg.cc.version}";
              version = "0.1";
              src = ./.;
              dontConfigure = true;
              buildInputs = [ pkgs.gmp ];
              buildPhase = ''
                make -C ./compiler-plugins/SoftwareCountersGccPlugin/
              '';
              installPhase = ''
                mkdir -p $out/lib64
                mkdir -p $out/share/doc/libSoftwareCountersGcc
                cp compiler-plugins/SoftwareCountersGccPlugin/COPYING $out/share/doc/libSoftwareCountersGcc
                cp compiler-plugins/SoftwareCountersGccPlugin/libSoftwareCountersGcc.so $out/lib64
                # provide an alias to make things easy when building rr.soft
                ln -s $out/lib64/libSoftwareCountersGcc.so $out/lib64/libSoftwareCounters.so
              '';
              meta = {
                homepage = "https://github.com/sidkshatriya/rr.soft";
                description = "libSoftwareCountersGcc";
                license = with pkgs.lib.licenses; [
                  gpl3Plus
                ];
                platforms = [
                  "aarch64-linux"
                  "x86_64-linux"
                ];
              };
            };
          libSoftwareCountersClangFor =
            llvmPackagesArg:
            llvmPackagesArg.stdenv.mkDerivation {
              pname = "libSoftwareCountersClang${pkgs.lib.versions.major llvmPackagesArg.stdenv.cc.version}";
              version = "0.1";
              src = ./.;
              nativeBuildInputs = [
                pkgs.cmake
                pkgs.ninja
                llvmPackagesArg.libllvm
              ];
              cmakeFlags = [
                "-S=${./.}/compiler-plugins/SoftwareCountersClangPlugin"
                "-GNinja"
              ];
              installPhase = ''
                mkdir -p $out/lib64
                mkdir -p $out/share/doc/libSoftwareCountersClang
                cp $src/compiler-plugins/SoftwareCountersClangPlugin/LICENSE $out/share/doc/libSoftwareCountersClang
                cp libSoftwareCountersClang.so $out/lib64
                # provide an alias to make things easy when building rr.soft
                ln -s $out/lib64/libSoftwareCountersClang.so $out/lib64/libSoftwareCounters.so
              '';
              meta = {
                homepage = "https://github.com/sidkshatriya/rr.soft";
                description = "libSoftwareCounters";
                license = with pkgs.lib.licenses; [
                  asl20
                ];
                platforms = [
                  "aarch64-linux"
                  "x86_64-linux"
                ];
              };
            };
          # pkgs.rr insists on using pkgs.gccMultiStdenv on x86_64, ignoring plain stdenv override.
          mkGccMultiStdenv = gccStdenvArg: pkgs.overrideCC gccStdenvArg (pkgs.wrapCCMulti gccStdenvArg.cc);
          mkClangMultiStdenv =
            clangStdenvArg: pkgs.overrideCC clangStdenvArg (pkgs.wrapClangMulti clangStdenvArg.cc);
          mkRrWithGcc =
            gccStdenvArg:
            (rr_compiled_with "gcc" (libSoftwareCountersGccFor gccStdenvArg)).override {
              stdenv = gccStdenvArg;
              gccMultiStdenv = mkGccMultiStdenv gccStdenvArg;
            };
          mkRrWithClang =
            llvmPackagesArg:
            (rr_compiled_with "clang" (libSoftwareCountersClangFor llvmPackagesArg)).override {
              stdenv = llvmPackagesArg.stdenv;
              gccMultiStdenv = mkClangMultiStdenv llvmPackagesArg.stdenv;
            };
        in
        {
          packages = {
            rr-builtwithgcc = mkRrWithGcc pkgs.gccStdenv;
            rr-builtwithgcc16 = mkRrWithGcc pkgs.gcc16Stdenv;
            rr-builtwithgcc15 = mkRrWithGcc pkgs.gcc15Stdenv;
            rr-builtwithgcc14 = mkRrWithGcc pkgs.gcc14Stdenv;
            rr-builtwithgcc13 = mkRrWithGcc pkgs.gcc13Stdenv;
            rr-builtwithclang = mkRrWithClang pkgs.llvmPackages;
            rr-builtwithclang22 = mkRrWithClang pkgs.llvmPackages_22;
            rr-builtwithclang21 = mkRrWithClang pkgs.llvmPackages_21;
            rr-builtwithclang20 = mkRrWithClang pkgs.llvmPackages_20;
            rr-builtwithclang19 = mkRrWithClang pkgs.llvmPackages_19;
            rr-builtwithclang18 = mkRrWithClang pkgs.llvmPackages_18;
            rr = self.packages.rr-builtwithclang;
            libSoftwareCountersGcc16 = libSoftwareCountersGccFor pkgs.gcc16Stdenv;
            libSoftwareCountersGcc15 = libSoftwareCountersGccFor pkgs.gcc15Stdenv;
            libSoftwareCountersGcc14 = libSoftwareCountersGccFor pkgs.gcc14Stdenv;
            libSoftwareCountersGcc13 = libSoftwareCountersGccFor pkgs.gcc13Stdenv;
            libSoftwareCountersClang22 = libSoftwareCountersClangFor pkgs.llvmPackages_22;
            libSoftwareCountersClang21 = libSoftwareCountersClangFor pkgs.llvmPackages_21;
            libSoftwareCountersClang20 = libSoftwareCountersClangFor pkgs.llvmPackages_20;
            libSoftwareCountersClang19 = libSoftwareCountersClangFor pkgs.llvmPackages_19;
            libSoftwareCountersClang18 = libSoftwareCountersClangFor pkgs.llvmPackages_18;
            default = self.packages.rr;
          };
        };
    };
}
