#!/usr/bin/env bash
# Initial local gittuf setup: only run once in the beginning, after `git init`.
# Run from the repository root.
#
# This will:
#   1. install and build the pinned gittuf binary (from github.com/yongjae354/gittuf/tree/generate-vsa)
#   2. generate root/policy/developer SSH keys (kept local, gitignored)
#   3. configure signed commits
#   4. initialize gittuf root of trust + policy (protect main, authorize developer)
#   5. create the developer-signed bootstrap commit
#   6. record main in the RSL
#   7. push the app + refs/gittuf/* to GitHub

set -euo pipefail

ORG="yongjae354"
REPO="supply-chain-integrity-demo"
LOCATION="git+https://github.com/${ORG}/${REPO}"
REMOTE="https://github.com/${ORG}/${REPO}.git" # HTTPS: pushes auth via the gh token

# 1. install and build the pinned gittuf binary

GITTUF_REPO="https://github.com/yongjae354/gittuf.git"
GITTUF_PIN="2dabe6f8e64a79293998c31090086267daab530e"
TOOLS_DIR="$(pwd)/.tools"
GITTUF_BIN="${TOOLS_DIR}/gittuf"

require_command() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "error: required command not found: $1" >&2
		exit 1
	}
}

require_command git
require_command go
require_command make
require_command mktemp
require_command ssh-keygen

mkdir -p "${TOOLS_DIR}"

gittuf_source="$(mktemp -d)"
trap 'rm -rf "${gittuf_source}"' EXIT

echo "Building gittuf at ${GITTUF_PIN}..."
git -C "${gittuf_source}" init --quiet
git -C "${gittuf_source}" remote add origin "${GITTUF_REPO}"
git -C "${gittuf_source}" fetch --quiet --depth=1 origin "${GITTUF_PIN}"
git -C "${gittuf_source}" checkout --quiet --detach FETCH_HEAD

actual_commit="$(git -C "${gittuf_source}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${GITTUF_PIN}" ]]; then
	echo "error: expected gittuf ${GITTUF_PIN}, fetched ${actual_commit}" >&2
	exit 1
fi

(
	cd "${gittuf_source}"
	GOBIN="${TOOLS_DIR}" make just-install
)

if [[ "${GITTUF_RUN_TESTS:-false}" == "true" ]]; then
	(
		cd "${gittuf_source}"
		make test
	)
fi

"${GITTUF_BIN}" version
export PATH="${TOOLS_DIR}:${PATH}"

# 2. generate root/policy/developer SSH keys

mkdir -p keys

for key_name in root policy developer; do
	if [[ ! -f "keys/${key_name}" ]]; then
		ssh-keygen -q -t ecdsa -N "" -f "keys/${key_name}"
	fi
done

# 3. configure signed commits

git config --local gpg.format ssh
git config --local user.signingkey "$(pwd)/keys/developer"
git config --local commit.gpgsign true

# 4. initialize the gittuf root of trust + policy

"${GITTUF_BIN}" trust init \
	-k keys/root \
	--location "${LOCATION}"

"${GITTUF_BIN}" trust add-policy-key \
	-k keys/root \
	--policy-key keys/policy.pub

"${GITTUF_BIN}" policy init \
	-k keys/policy \
	--policy-name targets

"${GITTUF_BIN}" policy add-person \
	-k keys/policy \
	--person-ID developer \
	--public-key keys/developer.pub

"${GITTUF_BIN}" policy add-rule \
	-k keys/policy \
	--rule-name protect-main \
	--rule-pattern git:refs/heads/main \
	--authorize developer

"${GITTUF_BIN}" policy stage --local-only
"${GITTUF_BIN}" policy apply --local-only

# 5. create the developer-signed bootstrap commit

git add .gitignore scripts/bootstrap-gittuf.sh
git commit -S -m "Add gittuf bootstrap"

# 6. record main in the RSL

"${GITTUF_BIN}" rsl record main --local-only

# 7. push the application and gittuf metadata

git remote add origin "${REMOTE}" 2>/dev/null ||
	git remote set-url origin "${REMOTE}"

git branch -M main
git push -u origin main
git push origin "refs/gittuf/*:refs/gittuf/*"

echo
echo "Bootstrap complete. gittuf metadata pushed to ${REMOTE}"
echo "For later changes:"
echo "  git commit -S ..."
echo "  ${GITTUF_BIN} rsl record main --local-only"
echo "  git push origin main 'refs/gittuf/*:refs/gittuf/*'"
