{
  description = "GlucoSync Kubernetes Infrastructure - NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Shared configuration for all nodes
      sharedModules = [
        ./nixos/common.nix
        ./nixos/modules/security.nix
      ];
    in
    {
      # NixOS configurations for different node types
      nixosConfigurations = {
        # Control plane node (includes HAProxy load balancer)
        glucosync-control-plane = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = sharedModules ++ [
            ./nixos/control-plane.nix
            ./nixos/modules/k3s-server.nix
          ];
        };

        # Worker node (optional - for multi-node clusters)
        glucosync-worker = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = sharedModules ++ [
            ./nixos/worker.nix
            ./nixos/modules/k3s-agent.nix
          ];
        };
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Development shell with all tools
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Kubernetes tools
            kubectl
            kubernetes-helm
            k9s
            kubectx
            kustomize

            # GitOps tools
            argocd

            # Container tools
            docker
            docker-compose

            # Monitoring tools
            prometheus
            grafana

            # Backup tools
            velero

            # Network tools
            curl
            wget
            jq
            yq

            # Development tools
            git
            gnumake

            # Nix deployment tools
            nixos-rebuild

            # MinIO client
            minio-client
          ];

          shellHook = ''
            echo "🚀 GlucoSync Kubernetes Development Environment"
            echo "================================================"
            echo "Available tools:"
            echo "  - kubectl, helm, k9s, kubectx"
            echo "  - argocd, velero"
            echo "  - docker, docker-compose"
            echo "  - mc (MinIO client)"
            echo ""
            echo "Deploy infrastructure:"
            echo "  nix run .#deploy-control-plane <IP>  # Control plane + HAProxy"
            echo "  nix run .#deploy-worker <IP>         # Worker node (optional)"
            echo "  nix run .#deploy-cluster              # Full automated deploy"
            echo ""
            echo "Note: Workers are optional. You can run everything on the control plane!"
          '';
        };

        # Apps for easy deployment
        apps = {
          # Deploy control plane (includes HAProxy)
          deploy-control-plane = {
            type = "app";
            program = toString (pkgs.writeShellScript "deploy-control-plane" ''
              set -e
              echo "🚀 Deploying GlucoSync Control Plane (with HAProxy)..."
              ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#glucosync-control-plane --target-host root@$1 --build-host localhost
            '');
          };

          # Deploy worker (optional)
          deploy-worker = {
            type = "app";
            program = toString (pkgs.writeShellScript "deploy-worker" ''
              set -e
              echo "🚀 Deploying GlucoSync Worker Node..."
              ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake .#glucosync-worker --target-host root@$1 --build-host localhost
            '');
          };

          # Full cluster deployment
          deploy-cluster = {
            type = "app";
            program = toString (pkgs.writeShellScript "deploy-cluster" ''
              set -e
              ${pkgs.bash}/bin/bash ${./scripts/deploy-cluster-nix.sh}
            '');
          };
        };
      }
    );
}
