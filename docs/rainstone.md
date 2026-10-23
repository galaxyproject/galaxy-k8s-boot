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
  CloudNativePG cluster. Rainstone changes nothing in Galaxy's database.
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

## Batch spend limit

With `enable_gcp_batch` on a single-user Galaxy, the playbook also enables
Rainstone's Batch spend limit, available but inactive until the user sets
a limit:

- A TPV rule on the `gcp_batch` destination asks Rainstone whether Batch is
  paused, using the `rainstone-dispatch` Secret. If Rainstone does not
  answer, jobs are admitted.
- Galaxy's `enable_notification_system` is on, so the collector can post
  notices about the limit.
- The collector receives the single user's Galaxy API key, in the
  `rainstone-galaxy-control` Secret, to post notices and stop jobs.
  Regenerating that key in Galaxy breaks this until the playbook runs
  again; the limit page shows the failure.

## Variables

```yaml
deploy_rainstone: true
rainstone_chart: cloudve/rainstone
rainstone_chart_version: "0.4.0"
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

## Release prerequisites

Chart `0.4.0` requires Rainstone `2.0.0b2`. Merge and publish the Rainstone
release before merging this playbook's chart-version update. Check the
published chart and image, rather than relying on a local package.

Galaxy 26.2's fair ready-job dispatch is required. The default AnVIL job
configuration and shared TPV database define no resubmission rules, so
this default deployment needs no Galaxy patch. Before adding resubmission
rules, select a Galaxy image that catches mapper deferral while recovering
a resubmitted job. Without that generic correction one waiting retry
aborts the handler poll before other ready jobs are processed. The
correction is prepared in Galaxy commit `284a6a6dbd`, pending review.

The guard is best effort. It covers cumulative recorded Batch compute,
including earlier costs, and excludes the Galaxy VM, disks and network.
It uses a ten-minute reaction allowance plus observation age and a $0.25
minimum margin. Turning a limit off releases waiting Batch jobs; stop
requests already sent continue to be checked and cannot be undone.
