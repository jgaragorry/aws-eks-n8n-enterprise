include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/eks-cluster"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id          = "vpc-fake-id"
    private_subnets = ["subnet-fake-1", "subnet-fake-2"]
  }
}

inputs = {
  project_name    = "gitops-platform"
  cluster_name    = "eks-gitops-dev"
  environment     = "dev"
  cluster_version = "1.29"

  # Configuración Spot (FinOps)
  instance_types = ["t3.medium"]
  min_size       = 1
  max_size       = 2
  desired_size   = 1

  # Red
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  # 👇 LA SECCIÓN MÁGICA (Driver)
  cluster_addons = {
    coredns = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }  # <--- ESTO ES LO NUEVO
  }
}
