{
  inputs = {
    nixpkgs.url = "github:nixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";

    wxWidgets = {
      url = "github:wxWidgets/wxWidgets";
      flake = false;
    };
    lk = {
      url = "github:NREL/lk";
      flake = false;
    };
    wex = {
      url = "github:NREL/wex";
      flake = false;
    };
    googletest = {
      url = "github:google/googletest";
      flake = false;
    };
    ssc = {
      url = "github:mjwagner2/ssc/solarpilot-develop";
      flake = false;
    };
    soltrace = {
      url = "github:NREL/SolTrace";
      flake = false;
    };
    solarpilot = {
      url = "github:NREL/SolarPILOT";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, systems, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ];
      systems = import systems;

      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          commonBuildInputs = with pkgs; [
            wxGTK32
            gtk3
            mesa
            freeglut
            libGLU
            curl
            nlopt
            lp_solve
            cmake
            pkg-config
            rapidjson
            curl
            pkgs.libGL
            glew
            mesa.drivers
          ];
          commonInstallPhase = p: ''
            mkdir -p $out/lib $out/include
            cp ${p}.a $out/lib/lib${p}.a
            cp -r ../include/* $out/include/
            if [ -f ${p}_sandbox ]; then
              mkdir -p $out/bin
              cp ${p}_sandbox $out/bin/
            fi
          '';
          wxGLFlags = pkgs.lib.concatStringsSep " " [
            "-L${pkgs.wxGTK32}/lib"
            "-lwx_gtk3u_gl-3.2"
            "-lwx_baseu_net-3.2"
            "-lwx_gtk3u_core-3.2"
            "-lwx_baseu-3.2"
          ];
          setWX = ''
            export WXMSW3=${pkgs.wxGTK32}
          '';
          commonCMakeFlags = [
            "-DCMAKE_BUILD_TYPE=Release"
            "-DwxWidgets_CONFIG_EXECUTABLE=${pkgs.wxGTK32}/bin/wx-config"
            "-DwxWidgets_ROOT_DIR=${pkgs.wxGTK32}"
            "-DCMAKE_INSTALL_LIBDIR=lib"
            "-DwxWidgets_USE_GL=ON"
          ];
        in {
          packages = {
            default = self'.packages.solarpilot;

            lk = pkgs.stdenv.mkDerivation {
              pname = "lk";
              version = "1.0.0";
              src = inputs.lk;

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc pkgs.pkg-config ];
              buildInputs = commonBuildInputs;

              cmakeFlags = commonCMakeFlags;

              preConfigure = setWX;

              installPhase = commonInstallPhase "lk";
            };

            wex = pkgs.stdenv.mkDerivation {
              pname = "wex";
              version = "1.0.0";
              src = inputs.wex;

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc pkgs.pkg-config ];
              buildInputs = commonBuildInputs
                ++ [ self'.packages.lk ];

              postPatch = ''
                rm -rf build_resources/libcurl_ssl_x64
                substituteInPlace src/easycurl.cpp \
                  --replace '../build_resources/libcurl_ssl_x64/include/curl/curl.h' \
                            'curl/curl.h'
              '';

              preConfigure = ''
                export WXMSW3=${pkgs.wxGTK32}
                export RAPIDJSONDIR=${pkgs.rapidjson}/include
                export CURL_DIR=${pkgs.curl.dev}
              '';

              cmakeFlags = commonCMakeFlags ++ [
                "-DLKDIR=${self'.packages.lk}"
                "-DSAM_SKIP_TOOLS=ON"
                "-DUSE_SYSTEM_CURL=ON"
              ];

              installPhase = commonInstallPhase "wex";
            };

            googletest = pkgs.stdenv.mkDerivation {
              pname = "googletest";
              version = "1.0.0";
              src = inputs.googletest;

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc ];

              cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
            };

            soltrace = pkgs.stdenv.mkDerivation {
              pname = "soltrace";
              version = "1.0.0";
              src = inputs.soltrace;

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc ];
              buildInputs = commonBuildInputs ++ [
                self'.packages.lk
                self'.packages.wex
                self'.packages.googletest
              ];

              CXXFLAGS = "-Wno-deprecated";
              #LDFLAGS="GL GLU GLEW";

              patches = [
                (pkgs.writeText "add-limits.patch" ''
                  diff --git a/coretrace/treemesh.cpp b/coretrace/treemesh.cpp
                  index xxxxxxx..xxxxxxx 100644
                  --- a/coretrace/treemesh.cpp
                  +++ b/coretrace/treemesh.cpp
                  @@ -53,6 +53,7 @@
                   #include <algorithm>
                  +#include <limits>

                   #include <unordered_map>
                   #include <set>
                '')
              ];

              cmakeFlags = commonCMakeFlags ++ [
                "-DLKDIR=${self'.packages.lk}"
                "-DWEXDIR=${self'.packages.wex}"
                "-DGTEST=${self'.packages.googletest}"
                # "-DCMAKE_CXX_FLAGS=-I${pkgs.wxGTK32}/include/wx-3.1 -I${pkgs.wxGTK32}/lib/wx/include/gtk3-unicode-3.1"
                # "-DCMAKE_EXE_LINKER_FLAGS=-L${self'.packages.lk}/lib -L${self'.packages.wex}/lib"
              ];

              preConfigure = ''
              export RAPIDJSONDIR=${pkgs.rapidjson}/include
              export NIX_LDFLAGS="-lGL -lGLU $NIX_LDFLAGS"
              '';

              installPhase = commonInstallPhase "soltrace";
            };

            ssc = pkgs.stdenv.mkDerivation {
              pname = "ssc";
              version = "1.0.0";
              src = inputs.ssc;

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc ];
              buildInputs = commonBuildInputs ++ [
                self'.packages.lk
                self'.packages.wex
                self'.packages.googletest
                self'.packages.soltrace
              ];

              preConfigure = ''
                cd nlopt
                ./configure
                make
                cd ..
              '';

              cmakeFlags = [
                "-DCMAKE_BUILD_TYPE=Release"
                "-DwxWidgets_CONFIG_EXECUTABLE=${pkgs.wxGTK32}/bin/wx-config"
                "-DLKDIR=${self'.packages.lk}"
                "-DWEXDIR=${self'.packages.wex}"
                "-DGTEST=${self'.packages.googletest}"
                "-DCORETRACEDIR=${self'.packages.soltrace}/coretrace"
              ];
            };

            solarpilot = pkgs.stdenv.mkDerivation {
              pname = "solarpilot";
              version = "1.0.0";
              src = inputs.solarpilot;

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc pkgs.makeWrapper ];
              buildInputs = commonBuildInputs ++ [
                self'.packages.lk
                self'.packages.wex
                self'.packages.googletest
                self'.packages.soltrace
                self'.packages.ssc
              ];

              cmakeFlags = [
                "-DCMAKE_BUILD_TYPE=Release"
                "-DwxWidgets_CONFIG_EXECUTABLE=${pkgs.wxGTK32}/bin/wx-config"
                "-DLKDIR=${self'.packages.lk}"
                "-DWEXDIR=${self'.packages.wex}"
                "-DGTEST=${self'.packages.googletest}"
                "-DCORETRACEDIR=${self'.packages.soltrace}/coretrace"
                "-DSSCDIR=${self'.packages.ssc}"
              ];

              installPhase = ''
                mkdir -p $out/bin
                cp deploy/x64/SolarPILOT $out/bin/
                wrapProgram $out/bin/SolarPILOT \
                  --prefix LD_LIBRARY_PATH : ${
                    pkgs.lib.makeLibraryPath commonBuildInputs
                  }
              '';
            };
          };
        };
    };
}
