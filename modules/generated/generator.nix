{
  prefix,
  mainDir,
  ignorePrefix ? ["_"],
  default ? "default",
  moduleSettings ? "moduleSettings",
  ...
}: {
  self,
  pkgs,
  lib,
  ...
} @ outerArgs: let
  lib' = self.lib';

  filtered = [moduleSettings];

  # Recusivly return all files in given directory in a list
  # str -> [ str ]
  getAllFiles = lib.filesystem.listFilesRecursive;

  # Checks if given string has prefix that is in the ignored array
  # str -> bool
  shouldIgnore = string: (builtins.any (prefix: lib.strings.hasPrefix prefix string) ignorePrefix);

  # Checks if file path has any part that indicates that it should be ignored
  # str -> bool
  shouldIgnoreFile = path: let
    parts = pathSplit path;
  in
    builtins.any shouldIgnore parts;

  # Filter list of files and removes ignored files that have prefix in any part of their path
  # [ str ] -> [ str ]
  filterIgnoredFiles = builtins.filter (file: !shouldIgnoreFile file);

  # Filter list of files and leave only those with .nix suffix
  # [ str ] -> [ str ]
  filterNixFiles = builtins.filter (lib.strings.hasSuffix ".nix");

  # Stplit file path into list of folders and then the file name
  # str -> [ str ]
  pathSplit = lib.strings.splitString "/";
  # Apply pathSplit to file with removed suffix ".nix"
  # str -> [ str ]
  pathToModuleParts = path: pathSplit (lib.strings.removeSuffix ".nix" (builtins.toString path));
  # Split file path and remove the common prefix (that being the path to the mainDir
  # and then prepend the prefix part
  # str -> [ str ]
  removeCommonPart = parts: prefix ++ lib.lists.drop (builtins.length (pathToModuleParts mainDir)) parts;

  # Create helper attrset with file name (path) and parts (options path)
  # str -> keyPath ({ path = str; parts: [ str ]; })
  mkNixKeyPath = path: {
    inherit path;
    parts = removeCommonPart (pathToModuleParts path);
  };

  # Apply mkNixKeyPath to list of files
  # [ str ] -> [ keyPath ]
  mkNixKeyPaths = builtins.map mkNixKeyPath;

  # Get all parent folders until mainDir
  # str -> [ str ]
  getParrentFolders = folder:
    [folder]
    ++ (
      if folder != mainDir
      then (getParrentFolders (builtins.dirOf folder))
      else []
    );

  # Get list of nixKeyPath folders that contain at least one .nix file or have sub folder with at least one nix file
  # [ keyPath ] -> [ keyPath ]
  nixKeyPathsToFolders = keyPaths:
    lib.lists.unique (
      builtins.concatMap (keyPath:
        builtins.map mkNixKeyPath (
          getParrentFolders (builtins.dirOf keyPath.path)
        ))
      keyPaths
    );

  # Return list of all files that have .nix suffix inside of a dir (recursively)
  # str -> [ str ]
  getNixFiles = dir: filterNixFiles (filterIgnoredFiles (getAllFiles dir));

  # Get all nixKeyPaths struct for each file under given folder
  # str -> [ keyPath ]
  getNixKeyPaths = dir: mkNixKeyPaths (getNixFiles dir);

  mkFileOption = keyPath: let
    settings = (getConfigFromFile keyPath.path)."${moduleSettings}" or {};
  in (lib.attrsets.recursiveUpdate {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "This option is autogenerated from file ${keyPath.path}.";
      };
    }
    settings);

  mkFolderOption = keyPath: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "This option is autogenerated option from folder containing nix files. Enabling this option will enable these subfiles:\n${
        let
          enabled = lib.attrsets.filterAttrsRecursive (n: _v: n != "enable") (generateFolderEnableAttrs keyPath.path);
        in
          lib.strings.concatMapStrings (option: " - " + option + "\n") (lib'.internal.getAttrsPaths enabled)
      }";
    };
  };

  generateOption = keyPath:
    if (builtins.length keyPath.parts) == 0
    then mkFileOption keyPath
    else {
      "${builtins.head keyPath.parts}" = generateOption {
        parts = builtins.tail keyPath.parts;
        inherit (keyPath) path;
      };
    };

  getConfigFromFile = keyPath: let
    configFile = keyPath;
    configContent = import configFile;
    isFunction = lib.isFunction configContent;
  in
    if isFunction
    then configContent (outerArgs // {inherit lib';})
    else configContent;

  generateConfig = {
    keyPath,
    configPath ? keyPath.parts,
  }: {config, ...}: {
    _file = keyPath.path;
    config =
      lib.mkIf
      (lib.attrsets.attrByPath (configPath ++ ["enable"]) false config)
      # Filter out my specific options used to configure the module generation
      (lib.attrsets.filterAttrs (n: _v: !builtins.elem n filtered) (getConfigFromFile keyPath.path));
  };

  enableOption = keyPath:
    if (builtins.length keyPath.parts) == 0
    then {enable = lib.mkDefault true;}
    else {
      "${builtins.head keyPath.parts}" = enableOption {
        inherit (keyPath) path;
        parts = builtins.tail keyPath.parts;
      };
    };

  enableAllSubOptions = builtins.foldl' (acc: keyPath: lib.attrsets.recursiveUpdate (enableOption keyPath) acc) {};

  filterEnabledIfDefault = attrset:
    if (attrset ? "_type" && attrset."_type" == "override")
    then attrset
    else
      (
        if lib.attrsets.hasAttrByPath [default] attrset
        then {inherit (attrset) default;}
        else lib.attrsets.mapAttrs (_n: filterEnabledIfDefault) attrset
      );

  # Generate attribute set used to enable files under give folder or default if present
  # Path to attribute set with leafs having enable set to mkDefault true
  # str -> {}
  generateFolderEnableAttrs = folder: filterEnabledIfDefault (enableAllSubOptions (getNixKeyPaths folder));

  generateFolderOption = keyPath:
    if (builtins.length keyPath.parts) == 0
    then mkFolderOption keyPath
    else {
      "${builtins.head keyPath.parts}" = generateFolderOption {
        parts = builtins.tail keyPath.parts;
        inherit (keyPath) path;
      };
    };

  generateFolderConfig = folder: {config, ...}: {
    _file = folder.path;
    config =
      lib.mkIf (lib.attrsets.attrByPath (folder.parts ++ ["enable"]) false config)
      (generateFolderEnableAttrs folder.path);
  };

  nixKeyPaths = getNixKeyPaths mainDir;

  foldersKeyPaths = nixKeyPathsToFolders nixKeyPaths;
in {
  options = lib.attrsets.recursiveUpdate (builtins.foldl' (acc: keyPath: lib.attrsets.recursiveUpdate (generateOption keyPath) acc) {} nixKeyPaths) (builtins.foldl' (acc: keyPath: lib.attrsets.recursiveUpdate (generateFolderOption keyPath) acc) {} foldersKeyPaths);
  imports = (builtins.map (keyPath: generateConfig {inherit keyPath;}) nixKeyPaths) ++ (builtins.map generateFolderConfig foldersKeyPaths);
}
