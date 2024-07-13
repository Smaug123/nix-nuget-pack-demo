{
  description = "Test NuGet";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:Smaug123/nixpkgs/nuget-deterministic";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pname = "TestNuGet";
      dotnet-sdk = pkgs.dotnet-sdk_8;
      dotnet-runtime = pkgs.dotnetCorePackages.runtime_8_0;
      version = "0.1";
      dotnetTool = dllOverride: toolName: toolVersion: hash:
        pkgs.stdenvNoCC.mkDerivation rec {
          name = toolName;
          version = toolVersion;
          nativeBuildInputs = [pkgs.makeWrapper];
          src = pkgs.fetchNuGet {
            pname = name;
            version = version;
            hash = hash;
            installPhase = ''mkdir -p $out/bin && cp -r tools/net6.0/any/* $out/bin'';
          };
          installPhase = let
            dll =
              if isNull dllOverride
              then name
              else dllOverride;
          in ''
            runHook preInstall
            mkdir -p "$out/lib"
            cp -r ./bin/* "$out/lib"
            makeWrapper "${dotnet-runtime}/bin/dotnet" "$out/bin/${name}" --add-flags "$out/lib/${dll}.dll"
            runHook postInstall
          '';
        };
    in {
      packages = {
        fantomas = dotnetTool null "fantomas" (builtins.fromJSON (builtins.readFile ./.config/dotnet-tools.json)).tools.fantomas.version (builtins.head (builtins.filter (elem: elem.pname == "fantomas") ((import ./nix/deps.nix) {fetchNuGet = x: x;}))).hash;
        fsharp-analyzers = dotnetTool "FSharp.Analyzers.Cli" "fsharp-analyzers" (builtins.fromJSON (builtins.readFile ./.config/dotnet-tools.json)).tools.fsharp-analyzers.version (builtins.head (builtins.filter (elem: elem.pname == "fsharp-analyzers") ((import ./nix/deps.nix) {fetchNuGet = x: x;}))).hash;
        default = pkgs.buildDotnetModule {
          inherit pname version dotnet-sdk dotnet-runtime;
          name = "TestNuGet";
          src = ./.;
          projectFile = "./WoofWare.Test.Thing/WoofWare.Test.Thing.fsproj";
          nugetDeps = ./nix/deps.nix; # `nix build .#default.passthru.fetch-deps && ./result` and put the result here
          doCheck = true;
        };
        nuget-package = let
          sdkSource = let
            version = dotnet-sdk.version;
          in
            pkgs.mkNugetSource {
              name = "dotnet-sdk-${version}-source";
              deps = pkgs.lib.lists.flatten [dotnet-sdk.packages];
            };
        in let
          nugetDeps = pkgs.mkNugetSource {
            name = "dotnet-package-nuget-source";
            description = "NuGet deps";
            deps = [
              (pkgs.mkNugetDeps {
                name = "dotnet-package";
                sourceFile = ./nix/deps.nix;
              })
            ];
          };
        in let
          nugetSource = pkgs.symlinkJoin {
            name = "my-nuget-source";
            paths = [nugetDeps sdkSource];
          };
        in let
          configFile = pkgs.substituteAll {
            name = "oh-whatever";
            src = ./nix-nuget.conf;
            nuget_source = "${nugetSource}";
          };
        in
          pkgs.stdenvNoCC.mkDerivation {
            name = "dotnet-package";
            src = ./.;
            buildInputs = [
              dotnet-sdk
            ];
            CONFIG_FILE = configFile;
            buildPhase = ''
              cp "$CONFIG_FILE" NuGet.config
              dotnet pack -c Release
            '';
            installPhase = ''
              cp WoofWare.Test.Thing/bin/Release/WoofWare.Test.Thing.*.nupkg "$out"
            '';
          };
      };
      devShell = pkgs.mkShell {
        buildInputs = [dotnet-sdk];
        packages = [
          pkgs.alejandra
          pkgs.nodePackages.markdown-link-check
          pkgs.shellcheck
        ];
      };
    });
}
