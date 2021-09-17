{ pkgs, ...}:

{
  programs.gnupg.agent.enable = true;
  
  environment.systemPackages = with pkgs; [
    # TUIS
    vim_configurable neovim
    htop 
    mc ranger

    # Commands
    neofetch cpufetch
    tmux openssh gnumake tldr nmap tree gcc
    killall thefuck nix-diff nix-index traceroute

    # man page
    man man-pages

    # Utilities
    wget curl git cmake gnupg lsof whois dnsutils file

    # Languages
    jdk jdk8 php nodejs nodePackages.npm
    python27Full python27Packages.virtualenv python27Packages.pip python27Packages.setuptools
    python37Full python37Packages.virtualenv python37Packages.pip python37Packages.setuptools
    python39Full python39Packages.virtualenv python39Packages.pip python39Packages.setuptools
    # --------------------------
  ];
   
  # man pages
  documentation.enable = true;
  documentation.man.enable = true;
  documentation.dev.enable = true;
 
}
