from liber_distill.quality import (
    evidence_is_exact,
    multiset_jaccard,
    output_policy_violations,
)


def test_exact_evidence():
    source = "Clearance is modelled with exp(ETA(1))."
    assert evidence_is_exact(["exp(ETA(1))"], source)
    assert not evidence_is_exact(["exp(ETA(2))"], source)


def test_sensitive_output_and_path_are_rejected(temp_config):
    value = "Email modeller@example.org and inspect C:\\Users\\person\\secret.txt."
    violations = output_policy_violations(value, temp_config.quality)
    assert "possible_personal_data" in violations
    assert "absolute_local_path" in violations


def test_near_duplicate_similarity():
    left = "Use the covariance condition number to assess numerical stability."
    close = "Use the covariance condition number to assess numerical stability."
    distant = "Simulate oral doses at twelve hour intervals."
    assert multiset_jaccard(left, close) == 1
    assert multiset_jaccard(left, distant) < 0.2
