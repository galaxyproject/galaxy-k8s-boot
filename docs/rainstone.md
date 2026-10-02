# Rainstone cost reports

[Rainstone](https://github.com/afgane/rainstone) reports Galaxy's compute
costs. The playbook installs it by default whenever it deploys Galaxy, as the
`rainstone` Helm release in the `galaxy` namespace, and Galaxy links it from
its masthead. Set `deploy_rainstone: false` to skip it.

## What the playbook configures

Rainstone is installed after Galaxy, from the `cloudve/rainstone` chart. Its
settings come from what the playbook has just deployed; none needs to be set
for the default deployment:

- Galaxy's database, read with the application credential named by Galaxy's
  CloudNativePG cluster. Rainstone changes nothing in Galaxy's database or
  configuration.
- The shared Galaxy account: Galaxy's `single_user`, or `galaxy_user` when
  Galaxy names none.
- Its address: `galaxy_prefix` followed by `/costs`, so it is routed wherever
  Galaxy is.
- The Galaxy server's identity and machine type, from the VM's instance
  metadata. Work that Galaxy runs with its local runner is reported as using
  the already-running server. Off GCP there is no metadata, and no server
  baseline is declared.
- The GCP Batch project and region, when `enable_gcp_batch` is on.

Cloud reads use the VM's existing credential. Rainstone needs no new IAM
binding.

## Variables

```yaml
deploy_rainstone: true
rainstone_chart: cloudve/rainstone
rainstone_chart_version: "0.3.0"
rainstone_base_path: "{{ galaxy_prefix | regex_replace('/$', '') }}/costs"
# Rainstone's instance identity. Keep it stable for a given Galaxy: a new slug
# starts a new reporting history.
rainstone_instance_slug: galaxy-galaxy
# The shared account, when Galaxy's configuration names no single_user.
rainstone_workspace_owner: "{{ galaxy_user }}"
# Chart values merged over the derived ones, e.g. an image tag.
rainstone_values: {}
# By default a failed install is reported without failing the playbook.
rainstone_required: false
```

## The masthead link

Behind the platform's proxy, Galaxy's masthead link is how Rainstone is
reached. Galaxy loads masthead webhooks only at startup, so the playbook
creates the link's `galaxy-webhook-rainstone` ConfigMap before installing
Galaxy, and Rainstone's chart is installed with its own webhook turned off.

## Storage and restoration

Rainstone's database uses the storage class of Galaxy's own database, so it is
kept on the same retained persistent disk across stop and resume. It gets its
own directory there and never shares Galaxy's data directory.

`restore_galaxy` does not restore Rainstone's database yet. On a new VM its
volume is provisioned afresh, and reporting history starts over.
