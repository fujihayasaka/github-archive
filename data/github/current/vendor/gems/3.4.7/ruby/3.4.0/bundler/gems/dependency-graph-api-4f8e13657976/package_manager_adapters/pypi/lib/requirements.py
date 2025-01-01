import re


def normalize_requirement_set(requirement_set):
    """
    Normalize the PyPI requirements format to the dependency graph
    requirements format. Some key differences:
    - The dependency graph uses '=' rather than '=='
    - The dependency graph uses '~>' rather than '~='
    - The dependency graph doesn't support version exclusions
    """
    if not requirement_set or not requirement_set.strip():
        return ''

    return ','.join(map(normalize_requirements, requirement_set.split(',')))


def normalize_requirements(requirements):
    match = re.search(r'(.*?)(\d.*)', requirements)

    if not match:
        return ''

    operator, version = match.group(1), match.group(2)
    operator = operator.strip().replace('==', '=').replace('~=', '~>')

    if operator == '!=':
        return "< {} || > {}".format(version, version)

    return "{} {}".format(operator, version)
