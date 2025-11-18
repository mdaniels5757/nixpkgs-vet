# Takes a path to nixpkgs and a path to the json-encoded list of `pkgs/by-name` attributes.
#
# Returns a value containing information on all Nixpkgs attributes which is decoded on the Rust
# side. See ./eval.rs for the meaning of the returned values.
{
  attrsPath,
  nixpkgsPath,
  configPath,
}:
let
  # attrs = builtins.trace "attrs: ${builtins.readFile attrsPath}" (builtins.fromJSON (builtins.readFile attrsPath));
  attrs = builtins.fromJSON (builtins.readFile attrsPath);
  byNameConfig = builtins.fromJSON (builtins.readFile configPath);
  byNameConfigIds = map (x: x.id) byNameConfig.by_name_dirs;
  getConfigById = id: builtins.head (builtins.filter (x: x.id == id) byNameConfig.by_name_dirs);
  # attrsByDir = let val = builtins.groupBy (x: x.by_name_dir_id) attrs; in builtins.trace "eval.nix:15: attrsByDir = ${builtins.toJSON val}" val;
  attrsByDir = builtins.groupBy (x: x.by_name_dir_id) attrs;
  packageNamesFromDir = dirId: if builtins.hasAttr dirId attrsByDir then map (x: x.package_name) attrsByDir.${dirId} else [ ];
  pkgSetForDir = dirId: if pkgs.lib.hasAttrByPath (getConfigById dirId).attr_path pkgs
                        then pkgs.lib.getAttrFromPath (getConfigById dirId).attr_path pkgs
                        else { };

  # We need to check whether attributes are defined manually e.g. in `all-packages.nix`,
  # automatically by the `pkgs/by-name` overlay, or neither. The only way to do so is to override
  # `callPackage` and `_internalCallByNamePackageFile` with our own version that adds this
  # information to the result, and then try to access it.
  overlay = final: prev: {

    # Adds information to each attribute about whether it's manually defined using `callPackage`
    callPackage =
      fn: args:
      addVariantInfo (prev.callPackage fn args) {
        # This is a manual definition of the attribute, and it's a `1callPackage`, specifically a
        # semantic `callPackage`.
        ManualDefinition.is_semantic_call_package = true;
      };

    # Adds information to each attribute about whether it's automatically defined by the
    # `pkgs/by-name` overlay. This internal attribute is only used by that overlay.
    #
    # This overrides the above `callPackage` information. It's OK because we don't need that one,
    # since `pkgs/by-name` always uses `callPackage` underneath.
    _internalCallByNamePackageFile =
      file: addVariantInfo (prev._internalCallByNamePackageFile file) { AutoDefinition = null; };
  };

  # We can't just replace attribute values with their info in the overlay, because attributes can
  # depend on other attributes, so this would break evaluation.
  addVariantInfo =
    value: variant:
    if builtins.isAttrs value then
      value // { _callPackageVariant = variant; }
    else
      # It's very rare that `callPackage` doesn't return an attribute set, but it can occur.
      # In such a case we can't really return anything sensible that would include the info, so just
      # don't return the value directly and treat it as if it wasn't a `callPackage`.
      value;

  pkgs = import nixpkgsPath {
    inherit byNameConfig;
    # Don't let the user's home directory influence this result.
    config = { };
    overlays = [ overlay ];
    # We check evaluation and `callPackage` only for x86_64-linux.  Not ideal, but hard to fix.
    system = "x86_64-linux";
  };

  # See AttributeInfo in ./eval.rs for the meaning of this.
  attrInfo = name: value: pkgSet: {
    location = builtins.unsafeGetAttrPos name pkgSet;
    attribute_variant =
      if !builtins.isAttrs value then
        { NonAttributeSet = null; }
      else
        {
          AttributeSet = {
            is_derivation = pkgs.lib.isDerivation value;
            # is_derivation = pkgs.lib.isDerivation (builtins.trace ["eval.nix:72: value:" value] value);
            definition_variant =
              if !value ? _callPackageVariant then
                { ManualDefinition.is_semantic_call_package = false; }
              else
                value._callPackageVariant;
          };
        };
  };

  # Information on all attributes that are in a by-name directory.
  byNameAttrsByDir = dirId: pkgSet:
  builtins.listToAttrs (
    map (name: builtins.trace "eval.nix:88: name = ${name}" {
      inherit name;
      value.ByName =
        if !(builtins.hasAttr name pkgSet) then
          { Missing = null; }
        else
          # Evaluation failures are not allowed, so don't try to catch them.
          { Existing = attrInfo name pkgSet.${name} pkgSet; };
    # }) (builtins.trace "eval.nix:96: calling packageNamesFromDir with dirId ${dirId}" (packageNamesFromDir dirId))
    }) (packageNamesFromDir dirId)
  );

  # Information on all attributes that exist but are not in `pkgs/by-name`.
  # We need this to enforce `pkgs/by-name` for new packages.
  nonByNameAttrsByDir = dirId: pkgSet: 
  builtins.mapAttrs (
    name: value:
    let
      # Packages outside `pkgs/by-name` often fail evaluation, so we need to handle that.
      output = attrInfo name value pkgSet;
      result = builtins.tryEval (builtins.deepSeq output null);
    in
    {
      NonByName = if result.success then { EvalSuccess = 
        # builtins.trace [(
        #   let str = "name = ${builtins.deepSeq name name}, output = ${builtins.toJSON (builtins.deepSeq output output)} value:";
        #   in builtins.deepSeq str str
        # ) value]
        builtins.trace
        (let val = ["eval.nix:117:" { inherit name output value; }]; in val)
        output
      ; } else { EvalFailure = null; };
    }
  ) (packageNamesFromDir dirId);
  # ) (builtins.removeAttrs pkgSet (builtins.trace "eval.nix:120: calling packageNamesFromDir with dirId ${dirId}" (builtins.trace "result of calling (packageNamesFromDir \"${dirId}\"): ${builtins.toJSON (packageNamesFromDir dirId)}" (packageNamesFromDir dirId))));

  # All attributes
  attributesForDir = dirId: pkgSet: pkgs.lib.recursiveUpdate (byNameAttrsByDir dirId pkgSet) (nonByNameAttrsByDir dirId pkgSet);
in
# We output them in the form [ [ <name> <value> ] ]` such that the Rust side doesn't need to sort
# them again to get deterministic behavior. This is good for testing.
# builtins.mapAttrs (dirId: attributes:
#   [
#     (map (name: [
#       name
#       attributes.${name}
#     ]) (builtins.attrNames attributes))
#   ]
# ) attrsByDir
let
  temp = map (dirId:
    let
        baseAttrPath = (getConfigById dirId).attr_path;
        pkgSet = pkgSetForDir dirId;
        attributes = (attributesForDir dirId pkgSet);
    in
      (map (name: [
        (baseAttrPath ++ [name])
        (attributes.${name})
      ]) (builtins.attrNames attributes))
  ) byNameConfigIds;
  temp' = builtins.concatLists temp;
in
temp'