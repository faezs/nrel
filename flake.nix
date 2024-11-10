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
          wxWidgets = pkgs.wxGTK32;
          commonBuildInputs = with pkgs; [
            wxGTK32
            gtk3
            mesa
            freeglut
            wxWidgets
            libGLU
            curl
            nlopt
            lp_solve
            cmake
            pkg-config
            rapidjson
            curl
            libGL
            glew
            mesa.drivers
          ];
          commonInstallPhase = p: ''
            mkdir -p $out/lib $out/include
            cp ${p}.a $out/lib/lib${p}.a
            cp ${p}.a $out/lib/${p}.a
            cp -r ../include/* $out/include/
            if [ -f ${p}_sandbox ]; then
              mkdir -p $out/bin
              cp ${p}_sandbox $out/bin/
            fi
          '';
          wxGLFlags = pkgs.lib.concatStringsSep " " [
            "-L${wxWidgets}/lib"
            "-lwx_gtk3u_gl-3.2"
            "-lwx_baseu_net-3.2"
            "-lwx_gtk3u_core-3.2"
            "-lwx_baseu-3.2"
          ];
          setWX = ''
            export WXMSW3=${wxWidgets}
          '';
          commonCMakeFlags = [
            "-DCMAKE_BUILD_TYPE=Release"
            "-DwxWidgets_CONFIG_EXECUTABLE=${wxWidgets}/bin/wx-config"
            "-DwxWidgets_ROOT_DIR=${wxWidgets}"
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

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc pkgs.pkg-config pkgs.mesa ];
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
                export WXMSW3=${wxWidgets}
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

              nativeBuildInputs = [ pkgs.cmake pkgs.gcc pkgs.makeWrapper ];
              buildInputs = commonBuildInputs ++ [
                self'.packages.lk
                self'.packages.wex
                self'.packages.googletest
                pkgs.gsettings-desktop-schemas
                pkgs.hicolor-icon-theme
                pkgs.shared-mime-info
                pkgs.vulkan-loader
                pkgs.xorg.libxcb
                pkgs.gdk-pixbuf
                pkgs.librsvg
                pkgs.adwaita-icon-theme
                pkgs.mesa.drivers
                pkgs.xorg.libX11
                pkgs.xorg.libXrender
                pkgs.xorg.libXdamage
                pkgs.xorg.libXext
              ];

              CXXFLAGS = "-Wno-deprecated";
              LDFLAGS = "-lGL -lGLU -lGLEW ${wxGLFlags}";

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
                "-DwxWidgets_USE_GL=1"
              ];

              preConfigure = ''
                export RAPIDJSONDIR=${pkgs.rapidjson}/include
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out/bin $out/lib $out/include
                cp -r /build/source/app/deploy/x64/SolTrace $out/bin/
                install -Dm644 coretrace/coretrace.a $out/lib/libcoretrace.a
                install -Dm644 coretrace/coretrace.a $out/lib/coretrace.a
                install -Dm755 coretrace/coretrace_api.so $out/lib/libcoretrace_api.so
                install -Dm755 coretrace/coretrace_api.so $out/lib/coretrace_api.so
                ls -lR ../coretrace
                cp ../coretrace/*.h $out/include/
                runHook postInstall
              '';

              postInstall = ''
                wrapProgram $out/bin/SolTrace \
                  --prefix XDG_DATA_DIRS : "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}" \
                  --prefix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
                  --prefix XDG_DATA_DIRS : "${pkgs.shared-mime-info}/share" \
                  --prefix XDG_DATA_DIRS : "${pkgs.adwaita-icon-theme}/share" \
                  --prefix GI_TYPELIB_PATH : "${pkgs.gtk3}/lib/girepository-1.0" \
                  --set GDK_PIXBUF_MODULE_FILE "${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" \
                  --set LIBGL_DRIVERS_PATH "${pkgs.mesa.drivers}/lib/dri" \
                  --set __EGL_VENDOR_LIBRARY_FILENAMES "${pkgs.mesa.drivers}/share/glvnd/egl_vendor.d/50_mesa.json" \
                  --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [
                    pkgs.gtk3
                    pkgs.mesa
                    pkgs.mesa.drivers
                    pkgs.libglvnd
                    pkgs.vulkan-loader
                    pkgs.xorg.libxcb
                    pkgs.gdk-pixbuf
                    pkgs.librsvg
                    pkgs.adwaita-icon-theme
                    pkgs.xorg.libX11
                    pkgs.xorg.libXrender
                    pkgs.xorg.libXdamage
                    pkgs.xorg.libXext
                  ]}" \
                  --set XCURSOR_PATH "${pkgs.gtk3}/share/icons" \
                  --set FONTCONFIG_FILE "${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
              '';
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

              postPatch = ''
                substituteInPlace solarpilot/interop.cpp \
                  --replace '#define HELIO_INTERCEPT false;' \
                            '#define HELIO_INTERCEPT false'
              '';

              preConfigure = ''
                cd nlopt
                ./configure
                cd ..
              '';

              NIX_CFLAGS_COMPILE = pkgs.lib.concatStringsSep " " [
                "-Wno-error"
                "-I${self'.packages.soltrace}/include"
                "-trigraphs"
              ];

              cmakeFlags = commonCMakeFlags ++ [
                "-DLKDIR=${self'.packages.lk}"
                "-DWEXDIR=${self'.packages.wex}"
                "-DGTEST=${self'.packages.googletest}"
                "-DCORETRACEDIR=${self'.packages.soltrace}"
              ];

              installPhase = ''
                runHook preInstall
                mkdir -p $out/{lib,include}
                cp nlopt/nlopt.a $out/lib/nlopt.a
                cp lpsolve/lpsolve.a $out/lib/lpsolve.a
                cp shared/shared.a $out/lib/shared.a
                cp solarpilot/solarpilot_core.a $out/lib/solarpilot_core.a
                # ls -R
                cp -r ../nlopt/*.h* $out/include/
                cp -r ../shared/*.h* $out/include/
                cp -r ../solarpilot/*.h* $out/include/

                runHook postInstall
              '';
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

              preConfigure = ''
                export LKDIR=${self'.packages.lk}
                export WEXDIR=${self'.packages.wex}
                export CORETRACEDIR=${self'.packages.soltrace}
                export SSCDIR=${self'.packages.ssc}
                export LK_LIB=${self'.packages.lk}/lib
                export WEX_LIB=${self'.packages.wex}/lib
                export CORETRACE_LIB=${self'.packages.soltrace}/lib
                export LPSOLVE_LIB=${self'.packages.ssc}/lib
                export NLOPT_LIB=${self'.packages.ssc}/lib
                export SHARED_LIB=${self'.packages.ssc}/lib
                export SPCORE_LIB=${self'.packages.ssc}/lib

              '';

              cmakeFlags = commonCMakeFlags ++ [
                "-DCMAKE_LIBRARY_PATH=${self'.packages.lk}/lib:${self'.packages.wex}/lib:${self'.packages.soltrace}/lib:${self'.packages.ssc}/lib"
                "-DwxWidgets_CONFIG_EXECUTABLE=${wxWidgets}/bin/wx-config"
                "-DLK_LIB=${self'.packages.lk}/lib/liblk.a"
                "-DWEX_LIB=${self'.packages.wex}/lib/libwex.a"
                "-DGTEST=${self'.packages.googletest}"
                "-DCORETRACE_LIB=${self'.packages.soltrace}/lib/libcoretrace.a"
                "-DSPCORE_LIB=${self'.packages.ssc}/lib/libsolarpilot_core.a"
                "-DSHARED_LIB=${self'.packages.ssc}/lib/libshared.a"
                "-DNLOPT_LIB=${self'.packages.ssc}/lib/libnlopt.a"
                "-DLPSOLVE_LIB=${self'.packages.ssc}/lib/liblpsolve.a"
              ];

              installPhase = ''
                mkdir -p $out/bin
                cp ../deploy/x64/SolarPILOT $out/bin/
                cp -r ../deploy/exelib $out/
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
