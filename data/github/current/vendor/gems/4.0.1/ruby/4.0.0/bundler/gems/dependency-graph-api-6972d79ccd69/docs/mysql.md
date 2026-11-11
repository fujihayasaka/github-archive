### Our Internal MySQL Database

Dependency Graph uses a MySQL database that is managed in-house by our amazing [@github/database-infrastructure](https://github.com/github/database-infrastructure) team. If you have any questions related to our database, make sure to reach out to them in Slack in the [`#databases` channel](https://github.slack.com/app_redirect?channel=databases).

### Useful Database Dashboards

#### Note on Proxima stamps

The links below assume the "`dependency-graph`" cluster, which is our production cluster. Proxima stamps have their own clusters, which you can find by searching ProfessorX and changing the links or dashboards below.

- [staffship:dependency-graph](https://professorx.githubapp.com/mysql/cluster/staffship:dependency_graph)

#### Dashboards

- [Our MySQL ProfessorX dashboard](https://professorx.githubapp.com/mysql/cluster/dependency-graph): Dashboard which lists all our database clusters, some useful commmands one can run on our databases via chatops, and servers where our databases are hosted.

- [Monitor for our MySQL table sizes](https://app.datadoghq.com/monitors/12804269): Shows the current size of our database, and whether we are getting close to the desired maximum size limit of the database. If we ever get to that size, an alert will be triggered.


- [Our MySQL Development Cluster](https://app.datadoghq.com/dashboard/xkj-uh2-hyh/mysql-development-cluster?tpl_var_cluster=dependency-graph): It shows the development cluster in broad strokes. CPU, Memory, IO & Network are the most basic resources that will constrain the cluster and of those, IO is often the constraint to be hit first.

- [Our MySQL Production Cluster](https://app.datadoghq.com/dashboard/33f-bma-8mc/mysqloverview?from_ts=1573077374638&is_auto=false&live=true&page=0&tile_size=m&to_ts=1573080974638&tpl_var_cluster=dependency-graph): It shows the production cluster in broad strokes. CPU, Memory, IO & Network are the most basic resources that will constrain the cluster and of those, IO is often the constraint to be hit first.

- [Vivid Cortex Profiler](https://githubinc.app.vividcortex.com/default/profiler?hosts=db-mysql-5b11556.cp1-iad.github.net%20db-mysql-01a2e6a.cp1-iad.github.net%20db-mysql-c11b4d4.cp1-iad.github.net%20db-mysql-c70641c.cp1-iad.github.net%20db-mysql-ccdf0bd.cp1-iad.github.net%20db-mysql-64f699a.sdc42-sea.github.net%20db-mysql-d008fb6.sdc42-sea.github.net%20db-mysql-53b53bd.ac4-iad.github.net%20db-mysql-6e8b3f7.ac4-iad.github.net%20db-mysql-6842dc6.ac4-iad.github.net%20db-mysql-c0cb912.va3-iad.github.net%20db-mysql-52a23ff.va3-iad.github.net%20db-mysql-7328874.ash1-iad.github.net%20db-mysql-7e81272.ash1-iad.github.net%20db-mysql-4a411f5.ash1-iad.github.net&from=-3600&until=0&limit=50&rank=queries&by=time&orderBy=-time&filterByQueryText=&filterByTagName=&filterByTagValue=&compareOffset=0&hideVCQueries=false&cols=mongoDeadlockCount): For all clusters, shows the most expensive queries we have running in dependency graph. You can also get to this dahboard by going to professorx and clicking the `Query Profiler` Button.
