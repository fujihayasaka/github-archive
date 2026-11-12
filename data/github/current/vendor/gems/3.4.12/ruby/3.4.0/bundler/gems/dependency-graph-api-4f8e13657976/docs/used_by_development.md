# Guide: Used By Development Locally

Would you like to see the Used By button on github.localhost? Read on!

## Getting Started
Before you get started, you'll need to have both GitHub and Dependency Graph API running locally.
Check out the documentation in GitHubber for tips on getting GitHub setup.

To get Dependency Graph running, clone the repo locally and:
- Run `script/bootstrap`
- Run `script/setup`
- Run `env RAILS_LOG_TO_STDOUT=true script/server`

In order to get GitHub to render the Used By button, you'll need to enable the feature flag and specify the
dependency-graph-api URL when starting your server:
```bash
# Navigate to your github/github directory, if you aren't already there:
cd github/github

# If this is your first time developing the button, enable the feature flag:
bin/toggle-feature-flag enable repository_dependents_dropdown

# Start the server:
env DEPENDENCY_GRAPH_API_URL=http://localhost:9596/query bin/server
```
  
## Creating a Package
Once you've got both GitHub and dependency-graph-api running locally you can create a fake Package object which will 
allow the Used By button to show up during local development.

1. If you don't already have one, [create a repository locally](http://github.localhost/new).
2. Obtain the database ID of your repository, by either:
    - Opening stafftools for your repository (hit the :rocket: in the top right corner) and navigate to Admin » Database and note the ID column.
    - Or using `bin/console` to find the `Repository` and getting the ID that way: `dat("monalisa/your-repo").id`
3. Navigate to your dependency-graph-api folder in your terminal.
4. Run the command to generate a fake Package:
   ```
   bin/rails r script/dev/create-package-for-repo --repo-id YOUR_ID --nwo "YOUR-REPO/NAME-WITH-OWNER"
   ```
5. :ice_cream:

Now, if you navigate to your repository page, you should see dependency-graph-api getting queried.

You may not be able to see the button being rendered. If so, use Inspect Element in the browser to see if there are any
hidden items in `ul.pagehead-actions` - they'll look like `<li hidden>`. If so, remove the hidden attribute and you should see the button.

## Troubleshooting

#### I can't see the button!

Here are some ideas:
- Ensure that when you load the repository page that you see dependency-graph-api serving a request. 
  - If you don't, ensure that you're starting `github/github` with the `DEPENDENCY_GRAPH_API_URL` specified.
  - If you do, copy the GraphQL query being shown in the logs. Consider trying to use an app like GraphiQL 
  to try querying Dependency Graph directly and seeing if you get results returned.
- Use Inspect Element in your browser to check if there is a hidden `<li>` tag in `ul.pagehead-actions`
  - If there is, manually remove the hidden attribute so you can see it.
  
If you see the request and verify that data is being returned by running the query manually, but you don't see a hidden
`<li>` element, you may need to clear Memcached locally: `echo "flush_all" | nc localhost 11211`

If that doesn't work, when in doubt, restart it out! Try quitting your `github/github` server and starting it again.

#### I don't want to keep using Inspect Element to make this `<li>` show up!
Me either! I'm sorry, I know, it sucks! As a workaround, you can modify the `show_used_by_button?` 
method in `Repositories::DetailView` to always return `true`. 
Just comment everything else out, `return true` and make sure you don't commit that! :innocent: