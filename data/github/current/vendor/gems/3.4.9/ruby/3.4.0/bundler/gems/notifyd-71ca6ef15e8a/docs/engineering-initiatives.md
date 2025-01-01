# Engineering Initiatives

We as an engineering team have a lot of suggestions which have an indirect impact on users. These could be technical, debt elimination, DevX or quality improvements.
In this document I would like to cover common questions about the process of bringing an idea to life.

## Who can suggest ?
Anyone from the team or outside of the team.

## How can I suggest an idea and bring them to the implementation stage?
**Step 1:** Document a problem statement. 
The Document should answer the question ‘Why?’ What is getting better, getting resolved or easier if we do this? It also can focus on the part ‘what is a risk of not doing?’. What can fail, stop working or cause slowness of engineering if we ignore this problem. 
Good to have description of KPI we are trying to improve - latency, code performance, code coverage, code maintainability, incidence rate, an incident time to detect/react/mitigate, process simplification. 


**Step 2:** Sharing the problem statement with the team.
No matter who is the author of the proposal or how obvious the problem is, the team is the decision maker on stage.  It is up to the team to agree or disagree with the importance of the improvement. 
If the team disagrees with the problem statement, the document stays in our repository for the future reference. No further actions are taken.
If the team agrees that the problem is important to solve, the proposal is moving to the stage of solution research and effort estimation. 

**Step 3:** Solution research and effort estimation. 
Sometimes the solution is straight forward or requires minimum effort to propose. Sometimes it requires an investigation to be done: spikes, deep dive into technology, new technology selection, consulting external parties, … 
If a solution is straightforward, please document and share with the team for feedback.
If more effort (1 day) is required, please create an issue for research, refine with the team on refinement session, and bring to sprint when available. When the team is settled on a decision about a solution, the proposal has to be evaluated from size and complexity.


**Step 4:** Size and complexity estimation. 
This process has given us clues: how complex and heavy a solution is? I would suggest using a simple model: XS, S, M, L, XL, XXL. As an example of S can be simple as an adding extra notifications for label added/update/removed, M we can take the Email Polish epic, XL could be Scale Label Subscription epic.  
It can be that the proposal is not that complex and parts of it are not connected, so there is no real sense to have an epic and we can easily take action after action to next sprints. 


Goal of this step to conclude if epic is needed, and what is estimated work/complexity. 

**Step 5:** Review with Product Manager. 
Review with the Product Manager can be done during: NotificationPlatform Sync meeting (bi-weekly) or asynchrony in the slack channel (@notification-platform).
  
Prioritization of work is done by the Product Manager. The team can suggest and try to convince, but at the end of the day it is the PM who says final Yes or No. Based on PM decision:
- The proposal can stay a proposal and never come to life.
- The proposal can be brought to next cycle immediately
- The proposal can be brought to cycle after the next one,..


 **Step 6:** Implementation. 


<img width="697" alt="image" src="https://user-images.githubusercontent.com/52420926/161025881-309d14d3-795f-4425-85cb-592261b6fb6b.png">


## What if I have a product idea?

Planing&Tracking organization has Pitch Process to suggest a Product ideas. Please find it [here](https://github.com/orgs/github/projects/3580/views/2).


  
