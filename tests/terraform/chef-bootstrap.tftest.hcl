mock_provider "azurerm" {
  mock_resource "azurerm_role_definition" {
    defaults = {
      role_definition_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/33333333-3333-4333-8333-333333333333"
    }
  }

  mock_resource "azurerm_role_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/44444444-4444-4444-8444-444444444444"
    }
  }
}
mock_provider "azapi" {}

variables {
  subscription_id                  = "00000000-0000-0000-0000-000000000000"
  tenant_id                        = "00000000-0000-0000-0000-000000000000"
  environment_name                 = "demo"
  backend_environment_name         = "demo"
  source_region                    = "eastus"
  burst_region                     = "southcentralus"
  burst_zone                       = "1"
  alternate_burst_placements       = []
  source_vnet_cidr                 = "10.10.0.0/16"
  burst_vnet_cidr                  = "10.20.0.0/16"
  operator_group_object_ids        = ["00000000-0000-0000-0000-000000000000"]
  scheduler_admin_ssh_public_key   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOZsLp0yT/oTDgPzOJBUK5vYbmOFwQKcXkyJbYcYlMe test"
  windows_admin_password           = "Valid-Test-Password-123!"
  cyclecloud_vm_size               = "Standard_D4s_v6"
  scheduler_vm_size                = "Standard_D4s_v6"
  windows_vm_size                  = "Standard_D2s_v6"
  burst_vm_size                    = "Standard_HB120rs_v3"
  cluster_name                     = "cross-region-demo"
  deployment_source_commit         = "0000000000000000000000000000000000000000"
  deployment_principal_id          = "11111111-1111-4111-8111-111111111111"
  backend_storage_account_name     = "stslurmdemoeus01a1b2"
  current_execution_context_digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  cyclecloud_image = {
    publisher = "azurecyclecloud"
    offer     = "azure-cyclecloud"
    sku       = "cyclecloud8-gen2"
    version   = "8.9.320260827"
    plan_name = "cyclecloud8-gen2"
    product   = "azure-cyclecloud"
  }
  scheduler_image = {
    publisher = "almalinux"
    offer     = "almalinux-x86_64"
    sku       = "9-gen2"
    version   = "9.8.2026100501"
  }
  burst_compute_image = {
    publisher = "almalinux"
    offer     = "almalinux-hpc"
    sku       = "9-hpc-gen2"
    version   = "9.8.202608110"
  }
  windows_image = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "26100.33438.260905"
  }

  backend_readiness_json = jsonencode({
    source_commit = "0000000000000000000000000000000000000000"
    assessed_at   = timestamp()
    status        = "ready"
    failure_class = "none"
    identity = {
      tenant_id    = "00000000-0000-0000-0000-000000000000"
      principal_id = "11111111-1111-4111-8111-111111111111"
    }
    execution_context = {
      runner_context_digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
    coordinates = {
      subscription_id      = "00000000-0000-0000-0000-000000000000"
      tenant_id            = "00000000-0000-0000-0000-000000000000"
      storage_account_name = "stslurmdemoeus01a1b2"
      container_name       = "tfstate"
      state_keys = {
        bootstrap      = "demo/bootstrap.tfstate"
        main           = "demo/main.tfstate"
        capacity_probe = "demo/capacity-probe.tfstate"
      }
    }
    checks = {
      account_context      = { status = "passed" }
      backend_exists       = { status = "passed" }
      container_exists     = { status = "passed" }
      dns                  = { status = "passed" }
      network              = { status = "passed" }
      authorization        = { status = "passed" }
      state_key_separation = { status = "passed" }
      migration            = { status = "passed" }
      locking              = { status = "passed" }
    }
  })

  chef_role_payloads = {
    cyclecloud = {
      policy_archive_base64 = base64encode("cyclecloud-policy-archive")
      manifest_json = jsonencode({
        schemaVersion             = 1
        role                      = "cyclecloud"
        sourceRevision            = "0000000000000000000000000000000000000000"
        policyName                = "cyclecloud"
        policyRevision            = "1111111111111111111111111111111111111111111111111111111111111111"
        policyLockSha256          = "2222222222222222222222222222222222222222222222222222222222222222"
        policyArchiveBase64Sha256 = sha256(base64encode("cyclecloud-policy-archive"))
        artifacts = [
          {
            name      = "cyclecloud.tgz"
            kind      = "policy"
            version   = "0000000000000000000000000000000000000000"
            uri       = null
            sha256    = "3333333333333333333333333333333333333333333333333333333333333333"
            sizeBytes = 25
          },
          {
            name      = "cyclecloud.lock.json"
            kind      = "policy-lock"
            version   = "1111111111111111111111111111111111111111111111111111111111111111"
            uri       = null
            sha256    = "2222222222222222222222222222222222222222222222222222222222222222"
            sizeBytes = 100
          }
        ]
        manifestDigest = "4444444444444444444444444444444444444444444444444444444444444444"
      })
    }
    scheduler = {
      policy_archive_base64 = base64encode("scheduler-policy-archive")
      manifest_json = jsonencode({
        schemaVersion             = 1
        role                      = "scheduler"
        sourceRevision            = "0000000000000000000000000000000000000000"
        policyName                = "slurm"
        policyRevision            = "5555555555555555555555555555555555555555555555555555555555555555"
        policyLockSha256          = "6666666666666666666666666666666666666666666666666666666666666666"
        policyArchiveBase64Sha256 = sha256(base64encode("scheduler-policy-archive"))
        artifacts = [
          {
            name      = "scheduler.tgz"
            kind      = "policy"
            version   = "0000000000000000000000000000000000000000"
            uri       = null
            sha256    = "7777777777777777777777777777777777777777777777777777777777777777"
            sizeBytes = 24
          },
          {
            name      = "slurm.lock.json"
            kind      = "policy-lock"
            version   = "5555555555555555555555555555555555555555555555555555555555555555"
            uri       = null
            sha256    = "6666666666666666666666666666666666666666666666666666666666666666"
            sizeBytes = 100
          }
        ]
        manifestDigest = "8888888888888888888888888888888888888888888888888888888888888888"
      })
    }
  }
}

run "scheduler_stages_without_converging" {
  command = plan

  assert {
    condition     = strcontains(base64decode(local.scheduler_custom_data), "CHEF_POLICY_NAME=slurm")
    error_message = "Scheduler custom data must invoke only the common staging bootstrap."
  }

  assert {
    condition     = !strcontains(base64decode(local.scheduler_custom_data), "converge-scheduler")
    error_message = "Scheduler custom data must not autonomously start convergence."
  }

  assert {
    condition     = local.chef_node_specifications.scheduler.clusterName == "cross-region-demo" && local.chef_node_specifications.scheduler.slurmIdentity.uid == 11100 && local.chef_node_specifications.scheduler.mungeIdentity.uid == 11101 && local.chef_node_specifications.scheduler.hpcUser.uid == 11200 && local.chef_node_specifications.scheduler.slurmVersion == "26.05.4-1.el9" && local.chef_node_specifications.scheduler.schedulerPrivateName == "${var.environment_name}-scheduler.cyclecloud.internal" && local.chef_node_specifications.scheduler.burstVmSize == var.burst_vm_size && local.chef_node_specifications.scheduler.registeredSlurmProjectVersion == "4.0.9"
    error_message = "The scheduler node specification must retain the governed cluster and account identities."
  }

  assert {
    condition     = output.scheduler_bootstrap.key_vault_role == "Key Vault Secrets User"
    error_message = "The scheduler identity must receive only Key Vault secret-read data-plane access."
  }

  assert {
    condition     = output.cyclecloud_deployment.chef_manifest_digest == jsondecode(base64decode(output.cyclecloud_deployment.chef_manifest_base64)).manifestDigest
    error_message = "The CycleCloud handoff must expose the canonical manifest digest separately from its transport hash."
  }

  assert {
    condition     = output.cyclecloud_deployment.chef_node_specification_digest == jsondecode(base64decode(output.cyclecloud_deployment.chef_node_specification_base64)).specificationDigest
    error_message = "The CycleCloud handoff must expose the canonical specification digest separately from its transport hash."
  }

  assert {
    condition     = length(module.scheduler_vm.public_ips) == 0
    error_message = "The scheduler VM must retain its zero-public-IP posture."
  }
}

run "foundation_omits_cyclecloud_system_principal_assignments" {
  command = plan

  variables {
    cyclecloud_identity_phase = "foundation"
  }

  assert {
    condition = (
      output.cyclecloud_identity_rbac.phase == "foundation" &&
      output.cyclecloud_identity_rbac.post_create_rbac_enabled == false &&
      output.cyclecloud_identity_rbac.system_principal_id == null
    )
    error_message = "Foundation must omit every CycleCloud system-principal assignment."
  }

  assert {
    condition     = length(module.cyclecloud_post_create_role_assignments.role_assignments) == 0
    error_message = "Foundation must pass no role assignments to the post-create AVM."
  }
}

run "post_create_rbac_derives_system_principal_and_exact_assignments" {
  command   = apply
  state_key = "valid-post-create"

  variables {
    cyclecloud_identity_phase = "post-create-rbac"
  }

  plan_options {
    target = [
      data.azapi_resource.cyclecloud_vm[0],
      azurerm_role_definition.cyclecloud_orchestrator,
      check.cyclecloud_system_identity_shape,
      module.cyclecloud_post_create_role_assignments,
    ]
  }

  override_module {
    target = module.resource_group
    outputs = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg"
    }
  }

  override_module {
    target = module.key_vault
    outputs = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg/providers/Microsoft.KeyVault/vaults/demo-vault"
    }
  }

  override_data {
    target          = data.azapi_resource.cyclecloud_vm[0]
    override_during = plan
    values = {
      output = {
        identity = {
          type                   = "SystemAssigned"
          principalId            = "22222222-2222-4222-8222-222222222222"
          userAssignedIdentities = {}
        }
      }
    }
  }

}

run "foundation_removes_only_post_create_assignments" {
  command   = apply
  state_key = "valid-post-create"

  variables {
    cyclecloud_identity_phase = "foundation"
  }

  plan_options {
    target = [
      azurerm_role_definition.cyclecloud_orchestrator,
      module.cyclecloud_post_create_role_assignments,
    ]
  }

  override_module {
    target = module.resource_group
    outputs = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg"
    }
  }

  override_module {
    target = module.key_vault
    outputs = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg/providers/Microsoft.KeyVault/vaults/demo-vault"
    }
  }

  assert {
    condition = (
      length(azurerm_role_definition.cyclecloud_orchestrator.assignable_scopes) == 1 &&
      contains(
        azurerm_role_definition.cyclecloud_orchestrator.assignable_scopes,
        "/subscriptions/00000000-0000-0000-0000-000000000000"
      )
    )
    error_message = "Returning to foundation must remove the post-create assignments and retain the custom role."
  }
}

run "foundation_assignment_removal_is_idempotent" {
  command   = apply
  state_key = "valid-post-create"

  variables {
    cyclecloud_identity_phase = "foundation"
  }

  plan_options {
    target = [
      azurerm_role_definition.cyclecloud_orchestrator,
      module.cyclecloud_post_create_role_assignments,
    ]
  }

  override_module {
    target = module.resource_group
    outputs = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg"
    }
  }

  override_module {
    target = module.key_vault
    outputs = {
      resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg/providers/Microsoft.KeyVault/vaults/demo-vault"
    }
  }

  assert {
    condition = (
      length(azurerm_role_definition.cyclecloud_orchestrator.assignable_scopes) == 1 &&
      contains(
        azurerm_role_definition.cyclecloud_orchestrator.assignable_scopes,
        "/subscriptions/00000000-0000-0000-0000-000000000000"
      )
    )
    error_message = "A repeated foundation apply must retain the approved custom role."
  }
}

run "post_create_rbac_rejects_user_assigned_identity_shape" {
  command   = plan
  state_key = "invalid-uami-shape"

  variables {
    cyclecloud_identity_phase = "post-create-rbac"
  }

  override_data {
    target          = data.azapi_resource.cyclecloud_vm[0]
    override_during = plan
    values = {
      output = {
        identity = {
          type        = "SystemAssigned, UserAssigned"
          principalId = "22222222-2222-4222-8222-222222222222"
          userAssignedIdentities = {
            "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo/providers/Microsoft.ManagedIdentity/userAssignedIdentities/forbidden" = {}
          }
        }
      }
    }
  }

  expect_failures = [check.cyclecloud_system_identity_shape]
}

run "post_create_rbac_rejects_non_system_identity_shape" {
  command   = plan
  state_key = "invalid-system-shape"

  variables {
    cyclecloud_identity_phase = "post-create-rbac"
  }

  override_data {
    target          = data.azapi_resource.cyclecloud_vm[0]
    override_during = plan
    values = {
      output = {
        identity = {
          type                   = "None"
          principalId            = "22222222-2222-4222-8222-222222222222"
          userAssignedIdentities = {}
        }
      }
    }
  }

  expect_failures = [check.cyclecloud_system_identity_shape]
}

run "reject_missing_role_payloads" {
  command = plan

  variables {
    chef_role_payloads = null
  }

  expect_failures = [terraform_data.chef_role_payload_gate]
}

run "accept_binary_cyclecloud_policy_archive" {
  command = plan

  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      cyclecloud = merge(var.chef_role_payloads.cyclecloud, {
        policy_archive_base64 = "/w=="
        manifest_json = jsonencode(merge(
          jsondecode(var.chef_role_payloads.cyclecloud.manifest_json),
          { policyArchiveBase64Sha256 = sha256("/w==") }
        ))
      })
    })
  }
}

run "reject_mismatched_policy_archive_transport" {
  command = plan

  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      cyclecloud = merge(var.chef_role_payloads.cyclecloud, {
        policy_archive_base64 = base64encode("stale-cyclecloud-policy-archive")
      })
    })
  }

  expect_failures = [var.chef_role_payloads]
}

run "reject_secret_manifest_field" {
  command = plan
  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      scheduler = merge(var.chef_role_payloads.scheduler, {
        manifest_json = jsonencode(merge(jsondecode(var.chef_role_payloads.scheduler.manifest_json), {
          password = "must-not-enter-terraform"
        }))
      })
    })
  }
  expect_failures = [var.chef_role_payloads]
}

run "reject_mutable_artifact_version" {
  command = plan
  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      scheduler = merge(var.chef_role_payloads.scheduler, {
        manifest_json = jsonencode(merge(jsondecode(var.chef_role_payloads.scheduler.manifest_json), {
          artifacts = [
            merge(jsondecode(var.chef_role_payloads.scheduler.manifest_json).artifacts[0], {
              version = "latest"
            }),
            jsondecode(var.chef_role_payloads.scheduler.manifest_json).artifacts[1]
          ]
        }))
      })
    })
  }
  expect_failures = [var.chef_role_payloads]
}

run "reject_role_mismatch" {
  command = plan
  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      scheduler = merge(var.chef_role_payloads.scheduler, {
        manifest_json = jsonencode(merge(jsondecode(var.chef_role_payloads.scheduler.manifest_json), {
          role = "cyclecloud"
        }))
      })
    })
  }
  expect_failures = [var.chef_role_payloads]
}

run "reject_source_revision_mismatch" {
  command = plan
  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      scheduler = merge(var.chef_role_payloads.scheduler, {
        manifest_json = jsonencode(merge(jsondecode(var.chef_role_payloads.scheduler.manifest_json), {
          sourceRevision = "9999999999999999999999999999999999999999"
        }))
      })
    })
  }
  expect_failures = [var.chef_role_payloads]
}

run "reject_node_identity_mismatch" {
  command = plan
  variables {
    slurm_uid_gid = 11102
  }
  expect_failures = [var.slurm_uid_gid]
}

run "reject_missing_lock_identity" {
  command = plan
  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      scheduler = merge(var.chef_role_payloads.scheduler, {
        manifest_json = jsonencode(merge(jsondecode(var.chef_role_payloads.scheduler.manifest_json), {
          policyLockSha256 = ""
        }))
      })
    })
  }
  expect_failures = [var.chef_role_payloads]
}

run "reject_oversized_custom_data" {
  command = plan
  variables {
    chef_role_payloads = merge(var.chef_role_payloads, {
      scheduler = merge(var.chef_role_payloads.scheduler, {
        policy_archive_base64 = base64encode(join("", [
          for index in range(1000) : "oversized-policy-archive-content-padding-0123456789-abcdefghij-ABCDEFGHIJ"
        ]))
        manifest_json = jsonencode(merge(
          jsondecode(var.chef_role_payloads.scheduler.manifest_json),
          {
            policyArchiveBase64Sha256 = sha256(base64encode(join("", [
              for index in range(1000) : "oversized-policy-archive-content-padding-0123456789-abcdefghij-ABCDEFGHIJ"
            ])))
          }
        ))
      })
    })
  }
  expect_failures = [terraform_data.scheduler_bootstrap_contract]
}
