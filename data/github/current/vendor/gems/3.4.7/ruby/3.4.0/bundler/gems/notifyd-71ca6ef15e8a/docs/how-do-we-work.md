# Team Proccess

Team runs a lightweight Scrum as an internal process. We are still learning and iterating on the process as we go. So, this document is a snapshot of the current state.

## What Are the Scrum Ceremonies?

These are the four key scrum ceremonies we use in the team:

1. Backlog refinement/triage (product backlog refinement)
2. Sprint planning
3. Daily scrum
4. Sprint retrospective

Sprint Review is excluded for now as the team has super small iterations and the demo is recorded in parent epic. Also, team does not do estimation of the issues works on as for now

## Backlog refinement/triage

Backlog refinement and prioritisation process is usually done by the product person in cooperation with the engineering team. In fact, as for now the engineering team has no product person present in the team. So, we came up with a different format of a refinement session. Main idea is to refine tickets to the state when we are confident that anyone can pick a ticket and start work without major questions asked. We answer two questions 'What is a goal of the issue? What is definition of done?' and sometimes it's possible to document 'How is it going to be done?'

**A few rules for the session:**

1. During the session we are trying to answer all questions and get as much clarity in the issue as possible.
2. This is not a session when we define priority of the tickets.
3. We collectively take a look at the tickets with a status of "[Backlog 📚](https://github.com/orgs/github/projects/3011/views/43)". If there is a level of priority in the list i.e. a ticket is likely to be done next week, individuals can jump the queue and prioritize conversation around these tickets.
4. Every issue should not take more than 15 minutes of discussion. If it takes longer, it means we are not ready and a person is selected to keep discovery of the ticket and bring this ticket to conversation in the next refinement session.
5. Once we all agree that an ticket is refined, we change the ticket status from "Backlog 📚" and to "Ready 🎽"

**Video overview:**

https://user-images.githubusercontent.com/1643158/153860338-f9f45ed8-b8fb-4eac-bc8a-ca7e2d6eccb5.mp4


## Sprint Planning

All the work in scrum is cyclic: it happens during recurring, time-boxed periods when scrum team members are focused on delivering something of value to the customer. These iterative periods are known as sprints, and they have the same duration each time, somewhere between one week and a month. Notification team selected a 2 weeks iteration duration as for now. Sprints follow one after another, without any pause between them. Every team sets the duration of their sprints themselves. But to start a sprint, the team must know what they are going to develop. This is exactly what the sprint planning ceremony is for.

The team gathers and starts to pull items from their product backlog into the sprint backlog. The team needs to carefully consider how many items to take on, as they will make a commitment to completing each item on the sprint backlog before the sprint ends.


## Daily scrum

The development team gather each day for a very brief period of time (limited to 15 minutes) to discuss their current progress and any blockers that prevent them from finishing their tasks. In essence the meeting is for the development team, and not an opportunity for the product owner or manager to put more work on them, make decisions about how the team should work, or comment on the pace of progress.

Below are the three typical questions every development team member answers during a standup meeting:

1. What did you do yesterday?
2. What are your goals for today?
3. Blockers
4. How close are we to hitting our goals? What’s your comfort level?

### Format (taking on account meeting is just 15 minutes):

2-3 minutes per person starting from the person who was last day before
if there is longer/bigger discussions, we ask relevant people to stay for after daily discussion

Important: do not be late for standup and be mindful about time when you are sharing your update

If a person cannot make for daily call, they should share status in the team slack channel.
The goal of daily scrum meetings is to look at how things are going and to make a plan for the next 24 hours that will keep the team on track to complete the work they committed to by the end of the sprint.

## Sprint retrospective

Sprint retrospectives are critical for scrum teams that want to constantly improve the efficiency and quality of their work.

All members of the scrum team attend sprint retrospective, which takes place after the sprint review. The team:

1. Inspect how the sprint went in terms of people, relationships, process, and tools.
2. Identify what went well and opportunities for improvement.
3. Create a plan with specific improvements to be carried out during the next sprint.

Step #3 is crucial and often neglected by inexperienced teams. In order to bring value, retrospectives need to be actionable. Simply uncovering areas of improvement without doing anything won’t bring results.

It is very important to convert action items into backlog issue and have them tracked as work items and keep getting update on those.
Note: Tooling for retrospective is still under exploration.

## How does the FR automation work?
You can find extended documentations about First Responder & Triage Process (here)[https://github.com/github/notifications/blob/master/docs/on-call-FR/first-responder-process.md].

