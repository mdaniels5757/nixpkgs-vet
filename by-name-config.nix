# Configure by-name directories in this file.
# Then build with `nix-build -A build` to automatically generate by-name-config-generated.json
# (Or, to generate manually, `nix-instantiate --eval --json --strict by-name-config.nix > by-name-config-generated.json`)
# In the attrsets that make up by_name_dirs:
#   * The aliases_path field is optional.
#   * The ID field must be short and unique.
#   * All non-wildcard attr_path_regexes must be mutually exclusive.
{
  by_name_dirs = [
    {
      id = "py";
      path = "pkgs/development/python-modules/by-name";
      attr_path = [ "python3Packages" ];
      attr_path_regex = "^(python3\\d*Packages|python3\\d*.pkgs)\\..*$";
      all_packages_path = "/pkgs/top-level/python-packages.nix";
      aliases_path = "/pkgs/top-level/python-aliases.nix";
    }
    {
      id = "tcl";
      path = "pkgs/development/tcl-modules/by-name";
      attr_path = [ "tclPackages" ];
      attr_path_regex = "^(tcl\\d*Packages)\\..*$";
      all_packages_path = "/pkgs/top-level/tcl-packages.nix";
    }
    {
      id = "main";
      path = "pkgs/by-name";
      attr_path = [ ];
      attr_path_regex = "^[^\\.]*$";
      all_packages_path = "/pkgs/top-level/all-packages.nix";
      aliases_path = "/pkgs/top-level/aliases.nix";
    }
  ];
}
