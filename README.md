# acme-service

A tiny HTTP service, shipped as a signed, verifiable binary. It's used as the subject of an **end-to-end supply-chain
integrity pipeline**. The service itself is deliberately trivial.

## Why?

Software supply-chain initiatives often begin with compliance requirements, and one of their first outputs is an SBOM.
SBOMs provide valuable inventory, but inventory alone does not establish integrity. It cannot prove that a release came
from policy-compliant source, that the build used that exact source, or that the binary you received is the artifact the
build produced.

How can we close these gaps? Signed attestations can provide verifiable evidence about each stage. A source verification
summary attestation (Source VSA) records the verified source commit, a build provenance attestation binds together that
commit and the resulting binary digests, and an SBOM attestation binds the SBOM to each binary digest.

This PoC demonstrates how authenticating those records and matching their commit and artifact hashes establishes an
end-to-end integrity chain from source to released binary. Anyone who consumes the artifact can independently verify
that evidence or use a policy engine to enforce additional requirements.

```text
Developer-signed commit
        │
        ▼
Phase 1: verify gittuf RSL against gittuf policy          source-vsa.yml
        │  sign VSA and publish it by commit C
        │
        ▼
Source VSA recording commit C + verified source level
        │
        │
        ▼
Phase 2: SLSA build provenance recording C          release.yml
        │
        │
        ▼
Built binary with SHA-256 digest D
        │
        ├── Phase 3: SPDX SBOM attestation binding the SBOM to binary digest D  release.yml
        │
        ▼
Phase 4: integrity verifier                           verify-chain.sh
        │  verify source, build, and SBOM signer identities
        │  C(provenance) == C(VSA)
        │  D(provenance) == SHA-256(binary)
        │  D(SBOM attestation) == SHA-256(binary)
        ▼
GitHub Release
        │
        └── Phase 5 (not implemented): signed TUF metadata would bind target → D
```

> gittuf is pinned to the experimental PR #728 (`generate-vsa`). Build provenance and SBOM attestations are persisted in
> GitHub's attestation store. The signed Source VSA is published to GHCR.

## What does this pipeline do?

For each binary, the pipeline connects two values:

- **C** — the Git commit whose source history and policy were verified by gittuf.
- **D** — the SHA-256 digest of the binary being verified.

The Source VSA records **C**. The SLSA build provenance records **C** and the digest of each output binary. The SBOM
attestation records the same binary digest **D** as its subject. Before publishing, the integrity verifier authenticates
each signer, confirms that the VSA and provenance record the same commit **C**, and confirms that the provenance, SBOM
attestation, and local binary identify the same digest **D**.

A valid signature shows that a statement came from the expected signer and was not modified. Matching the commit and
artifact hashes show that the independently signed statements describe the same release.

This PoC stops at integrity verification. Decisions such as which builders are allowed, which source levels are
acceptable, and how exceptions are handled belong in a policy layer. A dedicated policy engine can consume verified
evidence and enforce those organization-specific requirements.
