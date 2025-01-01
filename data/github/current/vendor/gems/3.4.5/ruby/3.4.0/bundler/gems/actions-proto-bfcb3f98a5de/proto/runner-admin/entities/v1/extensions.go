// Extension methods to be included in generated Go packages

package entitiesv1

func (h *GitHubEntityHierarchy) IsEmpty() bool {
	return (h == nil) || (h.EnterpriseId == nil && h.OrganizationId == nil && h.RepositoryId == nil)
}

func (h *GitHubEntityHierarchy) Parent() *GitHubEntityHierarchy {
	if h.IsEmpty() {
		return nil
	}

	candidate := GitHubEntityHierarchy{
		EnterpriseId:   h.EnterpriseId,
		OrganizationId: h.OrganizationId,
		RepositoryId:   h.RepositoryId,
	}

	// Walk the hierarchy from the deepest level to the shallowest level and
	// clear the first non-empty entry.
	if candidate.RepositoryId != nil {
		candidate.RepositoryId = nil
	} else if candidate.OrganizationId != nil {
		candidate.OrganizationId = nil
	} else if candidate.EnterpriseId != nil {
		candidate.EnterpriseId = nil
	}

	if candidate.IsEmpty() {
		return nil
	}

	return &candidate
}

func (h *GitHubEntityHierarchy) GetBillingOwnerID() *Identity {
	if h == nil {
		return nil
	}

	for _, id := range []*Identity{h.EnterpriseId, h.OrganizationId} {
		if id != nil {
			return id
		}
	}

	return nil
}
