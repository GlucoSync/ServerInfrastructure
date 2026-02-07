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
        # Control plane node
        glucosync-control-plane = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = sharedModules ++ [
            ./nixos/control-plane.nix
            ./nixos/modules/k3s-server.nix
          ];
        };

        # Worker node
        glucosync-worker = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = sharedModules ++ [
            ./nixos/worker.nix
            ./nixos/modules/k3s-agent.nix
          ];
        };

        # HAProxy load balancer node
        glucosync-haproxy = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = sharedModules ++ [
            ./nixos/haproxy.nix
          ];
        };
      };

      # Development shell with all tools
      devShells = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
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
              echo "  nix run .#deploy-control-plane"
              echo "  nix run .#deploy-worker"
              echo "  nix run .#deploy-haproxy"
            '';
          };
        }
      );

      # Apps for easy deployment
      apps = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Deploy control plane
          deploy-control-plane = {
            type = "app";
            program = "${pkgs.writeShellScript "deploy-control-plane" ''
              set -e
              echo "🚀 Deploying GlucoSync Control Plane..."
              nixos-rebuild switch --flake .#glucosync-control-plane --target-host root@$1 --build-host localhost
            ''}";
          };

          # Deploy worker
          deploy-worker = {
            type = "app";
            program = "${pkgs.writeShellScript "deploy-worker" ''
              set -e
              echo "🚀 Deploying GlucoSync Worker Node..."
              nixos-rebuild switch --flake .#glucosync-worker --target-host root@$1 --build-host localhost
            ''}";
          };

          # Deploy HAProxy
          deploy-haproxy = {
            type = "app";
            program = "${pkgs.writeShellScript "deploy-haproxy" ''
              set -e
              echo "🚀 Deploying HAProxy Load Balancer..."
              nixos-rebuild switch --flake .#glucosync-haproxy --target-host root@$1 --build-host localhost
            ''}";
          };

          # Full cluster deployment
          deploy-cluster = {
            type = "app";
            program = "${pkgs.writeShellScript "deploy-cluster" ''
              set -e
              ${pkgs.bash}/bin/bash ${./scripts/deploy-cluster-nix.sh}
            ''}";
          };
        }
      );
    };
}
