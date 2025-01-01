package mysql

type cluster struct {
	RO Executor
	RW TransactionExecutor
}

type Resolver interface {
	WriteExecutorForTable(table string) TransactionExecutor
	ReadOnlyExecutorForTable(table string) Executor
}

type resolver struct {
	defaultCluster  cluster
	clusterForTable map[string]cluster
}

func (r resolver) WriteExecutorForTable(table string) TransactionExecutor {
	c, ok := r.clusterForTable[table]
	if !ok {
		return r.defaultCluster.RW
	}
	return c.RW
}

func (r resolver) ReadOnlyExecutorForTable(table string) Executor {
	c, ok := r.clusterForTable[table]
	if !ok {
		return r.defaultCluster.RO
	}
	return c.RO
}

func NewDefaultResolver(
	mysql1RO Executor,
	authndRO Executor,
	collabRO Executor,
	lodgeRO Executor,
	authndRW TransactionExecutor,
) Resolver {

	mysql1Cluster := cluster{
		RO: mysql1RO,
		// no RW connection, trying to access mysql1 for writes will panic.
	}
	collabCluster := cluster{
		RO: collabRO,
		// no RW connection, trying to access collab for writes will panic.
	}
	lodgeCluster := cluster{
		RO: lodgeRO,
		// no RW connection, trying to access lodge for writes will panic.
	}
	return &resolver{
		defaultCluster: cluster{
			RO: authndRO,
			RW: authndRW,
		},
		clusterForTable: map[string]cluster{
			"integrations":                           mysql1Cluster,
			"integration_installations":              mysql1Cluster,
			"oauth_accesses":                         mysql1Cluster,
			"oauth_applications":                     mysql1Cluster,
			"organization_credential_authorizations": mysql1Cluster,
			"public_keys":                            mysql1Cluster,
			"user_sessions":                          mysql1Cluster,
			"users":                                  mysql1Cluster,

			"scoped_integration_installations":      collabCluster,
			"site_scoped_integration_installations": collabCluster,

			"authentication_tokens": lodgeCluster,
		},
	}
}

// TODO(chriskirkland): Remove this.  This should be identical to NewDefaultResolver after removing Maxwell.
func NewProximaResolver(
	mysql1RO Executor,
	authndRO Executor,
	collabRO Executor,
	lodgeRO Executor,
	authndRW TransactionExecutor,
) Resolver {

	mysql1Cluster := cluster{
		RO: mysql1RO,
		// no RW connection, trying to access mysql1 for writes will panic.
	}
	collabCluster := cluster{
		RO: collabRO,
		// no RW connection, trying to access collab for writes will panic.
	}
	lodgeCluster := cluster{
		RO: lodgeRO,
		// no RW connection, trying to access lodge for writes will panic.
	}
	return &resolver{
		defaultCluster: mysql1Cluster,
		clusterForTable: map[string]cluster{
			"programmatic_access_tokens": {
				RO: authndRO,
				RW: authndRW,
			},

			"scoped_integration_installations":      collabCluster,
			"site_scoped_integration_installations": collabCluster,

			"authentication_tokens": lodgeCluster,
		},
	}
}
