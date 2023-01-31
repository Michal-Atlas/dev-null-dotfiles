{
  config,
  pkgs,
  ...
}: {
  security.wrappers."mount.ntfs3g-suid" = {
    setuid = true;
    owner = "root";
    group = "root";
    source = "${pkgs.ntfs3g.out}/bin/ntfs-3g";
  };

  environment.systemPackages = with pkgs; [ntfs3g];

  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/B866D53266D4F25C";
    fsType = "ntfs3g-suid";
    options = ["user" "rw" "utf8" "noauto" "umask=000" "uid=1000"];
  };
}
