#!/usr/bin/env bash
# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# hack script for running a kind e2e
# TODO(bentheelder): replace this with kubetest integration
# Usage: SKIP="ginkgo skip regex" FOCUS="ginkgo focus regex" kind-e2e.sh 

set -o errexit
set -o nounset
set -o pipefail
set -x

# get and isntall `kind` to tempdir
TMP_GOPATH=$(mktemp -d)
trap 'rm -rf ${TMP_GOPATH}' EXIT
env "GOPATH=${TMP_GOPATH}" go get k8s.io/test-infra/kind
PATH="${TMP_GOPATH}/bin:${PATH}"

# build the base image
# TODO(bentheelder): eliminate this once we publish this image
kind build base
# build the node image w/ kubernetes
kind build node

# make sure we have e2e requirements
make -C "$(go env GOPATH)/src/k8s.io/kubernetes" all WHAT="cmd/kubectl test/e2e/e2e.test vendor/github.com/onsi/ginkgo"

# ginkgo regexes
FOCUS="${FOCUS:-"\\[Conformance\\]"}"
SKIP="${SKIP:-"Alpha|Kubectl|\\[(Disruptive|Feature:[^\\]]+|Flaky)\\]"}"

# arguments to kubetest for the e2e
KUBETEST_ARGS="--provider=skeleton --test --test_args=\"--ginkgo.focus=${FOCUS} --ginkgo.skip=${SKIP}\" --dump=$HOME/make-logs/ --check-version-skew=false"

# if we set PARALLEL=true, then skip serial tests and add --ginkgo-parallel to the args
PARALLEL="{PARALLEL:-false}"
if [[ "${PARALLEL}" == "true" ]]; then
    SKIP="${SKIP}|\\[Serial\\]"
    KUBETEST_ARGS="${KUBETEST_ARGS} --ginkgo-parallel"
fi

# disable errexit so we can manually cleanup
set +o errexit

# run kind create, if it fails clean up and exit failure
if ! kind create
then
    kind delete
    exit 1
fi

# export the KUBECONFIG
# TODO(bentheelder): provide a `kind` command that can be eval'ed instead
export KUBECONFIG="${HOME}/.config/kind-config-1"

# run kubetest, if it fails clean up and exit failure
if ! kubetest "${KUBETEST_ARGS}"
then
    kind delete
    exit 1
fi

# re-enable errexit now that we aren't trying to do any catch and cleanup
set -o errexit

# delete the cluster
kind delete
