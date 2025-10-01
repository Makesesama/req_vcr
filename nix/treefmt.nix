# treefmt.nix
{ pkgs, ... }:
{
  # Used to find the project root
  projectRootFile = "flake.nix";
  # Enable the terraform formatter
  programs.mix-format = {
    enable = true;
    package = pkgs.elixir;
  };

  programs.nixfmt = {
    enable = true;
  };
}
