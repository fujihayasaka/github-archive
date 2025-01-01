from requirements import normalize_requirement_set


def test_normalize_requirement_set():
    assert normalize_requirement_set('> 3.0.0') == '> 3.0.0'
    assert normalize_requirement_set('>=3.0.0') == '>= 3.0.0'
    assert normalize_requirement_set('==3.0.0') == '= 3.0.0'
    assert normalize_requirement_set('~= 2.2') == '~> 2.2'
    assert normalize_requirement_set('===foobar') == ''
    assert normalize_requirement_set('!= 2.0.0') == '< 2.0.0 || > 2.0.0'
    assert normalize_requirement_set('~= 2.0,<2.5') == '~> 2.0,< 2.5'
    assert normalize_requirement_set('') == ''
    assert normalize_requirement_set('  ') == ''
    assert normalize_requirement_set(None) == ''
