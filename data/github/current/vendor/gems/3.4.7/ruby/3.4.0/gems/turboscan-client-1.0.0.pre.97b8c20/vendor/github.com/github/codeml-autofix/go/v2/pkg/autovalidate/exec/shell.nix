{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    # nativeBuildInputs is usually what you want -- tools you need to run
    nativeBuildInputs = with pkgs.buildPackages; [ nodejs_24 curl ];
    shellHook = ''
      npm install eslint@9.32.0 @eslint/js@9.32.0 typescript@5.9.2 typescript-eslint@8.43.0 globals@16.4.0
      npm install jschardet@latest lodash@^4.17.14 utf8@^3.0.0
      curl -L https://raw.githubusercontent.com/microsoft/sarif-js-sdk/e8b2911611cdca34eb9b0f572ec6ef485b3bf10d/packages/eslint-formatter-sarif/sarif.js > sarif.js
    '';
}