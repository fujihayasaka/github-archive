# Connecting to the Authnd Database

Database connection info is found on `https://professorx.githubapp.com`

You will need to be connected to the VPN to connect to these databases. More on that [here](https://github.com/github/vpn)

Adding these functions to your `.zshrc` or `.bashrc` can be handy for quickly connecting to prod authnd database:

```bash
function mysql-authnd-production() {
  /usr/bin/open -a "/Applications/Google Chrome.app" 'https://professorx.githubapp.com/mysql/cluster/authnd-production'
  /usr/local/opt/mysql@5.7/bin/mysql authnd_production -h db-mysql-authnd-production-ro.service.github.net -u authnd_production_ro_0 -p
}
```
