{
  description = "NREL's solarPILOT software";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Source repositories
    lk-src = {
      url = "github:NREL/lk";
      flake = false;
    };
    wex-src = {
      url = "github:NREL/wex";
      flake = false;
    };
    soltrace-src = {
      url = "github:NREL/SolTrace";
      flake = false;
    };
    solarpilot-src = {
      url = "github:NREL/SolarPILOT";
      flake = false;
    };
    ssc-src = {
      url = "github:mjwagner2/ssc/solarpilot-develop";
      flake = false;
    };
    googletest-src = {
      url = "github:google/googletest";
      flake = false;
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" "x86_64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }:
      let
        # Build wxWidgets with specific flags
        wxGTK-static = pkgs.wxGTK32;

        # Common build inputs
        commonBuildInputs = with pkgs; [
          wxGTK-static
          curl.dev
          openssl
          nlopt
          lp_solve
          fontconfig
          libGL
          freeglut
          gtk3
          mesa
          xorg.libX11
          xorg.libXxf86vm
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXinerama
        ];

        # Function to setup source tree
        setupSourceTree = pkgs.writeShellScriptBin "setup-source-tree" ''
          # Create working directory structure
          mkdir -p spt_dev/{lk,wex,ssc,SolTrace,SolarPILOT,googletest}

          # Copy sources to correct locations
          cp -r ${inputs.lk-src}/* spt_dev/lk/
          cp -r ${inputs.wex-src}/* spt_dev/wex/
          cp -r ${inputs.ssc-src}/* spt_dev/ssc/
          cp -r ${inputs.soltrace-src}/* spt_dev/SolTrace/
          cp -r ${inputs.solarpilot-src}/* spt_dev/SolarPILOT/
          cp -r ${inputs.googletest-src}/* spt_dev/googletest/

          # Create umbrella CMakeLists.txt
          cat > spt_dev/CMakeLists.txt << 'EOF'
          option(SAM_SKIP_TOOLS "Skips the sdktool and tcsconsole builds" ON)
          cmake_minimum_required(VERSION 3.12)

          Project(solarpilot_ui)
          #Project(solarpilot_api)

          if($${CMAKE_PROJECT_NAME} STREQUAL "solarpilot_api")
                  option(COPILOT_API "Builds library for Copilot API" ON)
          endif()

          if($${CMAKE_PROJECT_NAME} STREQUAL "solarpilot_ui")
                  add_subdirectory(lk)
                  add_subdirectory(wex)
          endif()

          add_subdirectory(ssc)
          add_subdirectory(SolTrace/coretrace)

          if($${CMAKE_PROJECT_NAME} STREQUAL "solarpilot_ui")
                  add_subdirectory(SolarPILOT)
          endif()
          EOF

          # Make files writable
          chmod -R u+w spt_dev

          # # Build googletest
          # cd spt_dev/googletest
          # mkdir -p build
          # cd build
          # cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=-std=c++11
          # make -j$NIX_BUILD_CORES
        '';

      in {
        packages = {
          setup-tree = setupSourceTree;

          default = pkgs.stdenv.mkDerivation {
            pname = "solarpilot";
            version = "1.0.0";

            # Create combined source
            src = pkgs.runCommand "solarpilot-combined-src" {} ''
              ${setupSourceTree}/bin/setup-source-tree
              cp -r spt_dev $out
            '';

            nativeBuildInputs = with pkgs; [
              cmake
              pkg-config
              gtk2
              nlopt
              gcc
              gpp
              git
              libcurl14-openssl
              build-essential

            ];

            buildInputs = commonBuildInputs;

            cmakeFlags = [
              "-DCMAKE_BUILD_TYPE=Release"
              "-DwxWidgets_CONFIG_EXECUTABLE=${wxGTK-static}/bin/wx-config"
              "-DGTK2_LIBRARIES=${pkgs.gtk3}/lib"
            ];

            installPhase = ''
              mkdir -p $out/bin
              cp SolarPILOT/deploy/aarch64/SolarPILOT $out/bin/
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [ self'.packages.setup-tree ];

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
            gcc
            gdb
            ninja
            gtk3
          ];

          buildInputs = commonBuildInputs;

          shellHook = ''
            export WXMSW3="${wxGTK-static}"
            export WX_CONFIG="${wxGTK-static}/bin/wx-config"
            export GTK3_LIBRARIES=${pkgs.gtk3}/lib
            export wxWidgets_LIBRARIES=${wxGTK-static}/lib
            export wxWidgets_INCLUDE_DIRS=${wxGTK-static}/include

            # Create development directory structure if it doesn't exist
            if [ ! -d "spt_dev" ]; then
              setup-source-tree
            fi

            # Set up environment variables as expected by build
            export GTEST="$PWD/spt_dev/googletest/googletest"
            export LKDIR="$PWD/spt_dev/lk"
            export WEXDIR="$PWD/spt_dev/wex"
            export SSCDIR="$PWD/spt_dev/ssc"
            export CORETRACEDIR="$PWD/spt_dev/SolTrace/coretrace"
          '';
        };
      };
    };
}
