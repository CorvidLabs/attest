---
hi: 1
families: [POLICY]
---

# The bar a commit has to clear

## Intent

A policy should be a short plain file in the repo that says what evidence a commit needs before anybody treats it as trusted, and nothing more exotic than that. Defaults are permissive so adopting attest never reddens a repo on its first day, and each rule maps to something a team actually argues about: was anything reviewed at all, did tests pass, was a human involved once the risk got real, whose key counts, and how recently. A misspelled rule is a rule that is switched off, so the file must be read strictly and complained about loudly. Above all the documentation has to be honest about which rules prove what was claimed and which prove who claimed it.

## Criteria

- **POLICY-1**  A policy is a small plain JSON file in the repo, with no new configuration language to learn.
  - **POLICY-1.a**  A policy sitting in the repo's usual place is picked up without my naming it.
- **POLICY-2**  Every rule is optional, so a policy can say as little as I want it to.
- **POLICY-3**  A policy that says nothing still asks each commit for at least one attestation.
- **POLICY-4**  A repo that has recorded nothing yet can adopt attest without anything turning red.
- **POLICY-5**  An operator can require that every commit carries an attestation.
- **POLICY-6**  An operator can require that some record says the tests passed.
- **POLICY-7**  An operator can require a valid signature somewhere on the commit.
- **POLICY-8**  An operator can set a floor on the confidence a commit has to reach.
- **POLICY-9**  An operator can demand a human sign-off once a recorded verdict is serious enough.
  - **POLICY-9.a**  That human sign-off can be its own separate record instead of a rewrite of the agent's.
- **POLICY-10**  An operator can demand a signature once a recorded verdict is serious enough.
- **POLICY-11**  An operator can demand passing tests once a recorded verdict is serious enough.
  - **POLICY-11.a**  A commit whose verdicts all sit below the threshold is left alone by these rules.
- **POLICY-12**  An operator can say which reviewers count at all.
  - **POLICY-12.a**  A whole role can be allowed at once, so any human counts without naming each one.
- **POLICY-13**  An operator can name the keys that count as trusted signers.
- **POLICY-14**  An operator can pin a named reviewer to a key, so nobody else can sign in their name.
  - **POLICY-14.a**  Reviewers nobody pinned are left unaffected by pinning.
- **POLICY-15**  An operator can require the trust to be recent, so a sign-off from months ago stops clearing today's commit.
  - **POLICY-15.a**  One fresh record clears a commit even when staler ones sit beside it.
  - **POLICY-15.b**  The same freshness question always gets the same answer, rather than drifting with whatever clock happened to be read.
- **POLICY-16**  The documentation is blunt about which rules prove what was claimed and which prove who claimed it.
- **POLICY-17**  A rule name I misspelled is an error, never a rule that silently does nothing.
  - **POLICY-17.a**  That error names the offending key and lists the real rule names.
- **POLICY-18**  A policy file I pointed at that is not there is an error, never a quiet fall back to letting everything through.
  - **POLICY-18.a**  A repo simply having no policy file is still fine when I did not ask for one by name.
- **POLICY-19**  A policy file that is not valid JSON is explained in words, naming the file and where the trouble is.
- **POLICY-20**  A policy is judged against everything recorded on a commit, so the evidence can be spread across several records.
