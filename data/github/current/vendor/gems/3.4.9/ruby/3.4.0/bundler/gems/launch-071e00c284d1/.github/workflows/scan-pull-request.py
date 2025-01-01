import json
import os
import re
import sys
import time
from github import Github, PullRequest

github = Github(os.getenv("GITHUB_TOKEN"))
data = json.loads(os.getenv("GITHUB_CONTEXT"))

risk = re.compile("\[x\] \*\*(\w+) risk\*\*", re.I|re.M)
high_risk_files = list(map(lambda v: re.compile(v), ["flow/flowevents/extraction.go", "credz"]))

# Wait 1 minute to give people time to fill out the PR body. Don't want to go to long to hold up builds,
# but slightly easier than a schedule or something else.
time.sleep(60) 

# Then reget the pull request.
repo = github.get_repo("%s/%s" % (data["event"]["repository"]["owner"]["login"], data["event"]["repository"]["name"]))
pull_request = repo.get_pull(data["event"]["pull_request"]["number"])
body = pull_request.body
files = pull_request.get_files()

for label in pull_request.get_labels():
  if label.name == "risk-assessed":
    print("Already labelled risk-assessed, so ignoring.")
    sys.exit()
    
# The message we'll put on the message at the end.
msg = []
# Let's assume that by default it isn't high risk
should_be_high = False
# Let's see if the user set it to high risk
is_high = False
# Parse the body to find if it's high risk
risks = risk.findall(body)

# Oops no risk assessment filled out.
if not risks:
  msg.append("It looks like you forgot to complete the risk assessment on this pull request, please complete it. We'll try to calculate risk anyway.")

# You said it's high, cool.
if "High" in risks:
  print("Setting to `is_high` because of the pull request body")
  is_high = True

for file in files:
  for regex in high_risk_files:
    if regex.search(file.filename):
      should_be_high = True
      print("Setting to `should be high` because of file: %s" % file.filename)
  
# You didn't say it was high, but we thought it should be.
if should_be_high:
  msg.append("We think this pull request should be high risk, so we've added that label. Reviews will likely take longer, sorry 😢.")

if should_be_high or is_high:
  pull_request.add_to_labels("high-risk")
  msg.append("""It looks like the risk assessment for this pull request is set to high. Before deploying this please:
* Use [lab to test the release](https://github.com/github/c2c-actions-experience/blob/main/doc/deploy-environments.md#to-use-actions-lab)
* Use [canary before a full deploy](https://github.com/github/c2c-actions-experience/blob/main/doc/deploy-environments.md#to-use-actions-canary)
* Consider if your change requires additional outer-loop testing. See [`actions/canary`](https://github.com/actions/canary) and [`github/sauron`](https://github.com/github/sauron) for existing test cases.
""")

# If there's anything to say, add a nice preamble and then comment on the issue.
if msg:
  msg.insert(0, "Hi 👋 from a bot to help evaluate the risk of this pull request and keep our service 💚.")
  pull_request.create_issue_comment(body="\n\n".join(msg))

pull_request.add_to_labels("risk-assessed")
