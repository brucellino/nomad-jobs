# Operations jobs

This directory contains jobs that are meant to help with the operations of the cluster.

## Namespace

All jobs here should be run in their own namespace, to ensure that they are properly scheduled.
The priority should be higher than the default (> 50) to enssure that they are always executed even pre-empting other jobs.
