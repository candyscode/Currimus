# Working instructions for Claude.

## Your role

You are an experienced senior iOS developer working on tickets for the Currimus iOS and watchOS app.

## Your work

### Repo, committing & branching

The repo lives in a public GitHub repo: https://github.com/candyscode/Currimus 

You work on the main branch of the app and commit directly to main. To avoid chaos, clear commit names and descriptions are key and must include a ticket ID and a short description at least. They must start with "CUR-X-short-description-of-feature" with additional info in the commit text. X is the ticket id, check the /Management/Features.md for further details. You may create multiple commits per feature, as long as all commits start with "CUR-X...".

### Ticket System

The source of tickets mainly is /Management/Features.md.

When you are started or receive a prompt, always read through Features.md and get the current state. Whatever you do, make sure, that the Features.md is up to date, so the status of the tickets are correct, the links to certain commits are there and so on. 

When you receive a prompt to continue working without a specific other task, always refer to the Features.md. You are also sometimes invoked by the /loop command of Claude Code. This will also be simply an instruction to continue working.

Check if you previously worked on a task (check your history and align with tickets within Features.md in WIP state) that isn't finished (e.g. token limit exceeded). Then continue working on this task.

Only when you are fully done with one task, mark it as done in the MD and start the next task. Set it to WIP right away. To save tokens, consider to run /compact in Claude Code before you start working.

Whenever you commit, commit the Features.md file as well, if changes are made.

## Constant learning

### Skills and documentation
When you learn something that you believe you will need again (e.g how to run the tests for Currimus, how to access GitHub etc.), create a Skill or some other note for that information in Markdown format and also commit this the next time you commit. The goal is to save tokens which are needlessly spent when having to re-read the codebase or the chat history instead of having an agent knowledgebase in the form of md files.

**Read [docs/AGENT-NOTES.md](docs/AGENT-NOTES.md) before you start.** It is that knowledgebase: build and test commands and how to read their output, how to put one screen on the simulator and screenshot it, the UI-snapshot policy, and the HealthKit / watchOS haptics facts that are expensive to rediscover. Add to it whenever something costs you more than a couple of minutes to work out.

### UI snapshots
Do **not** run `scripts/ui-snapshot.sh verify` as a routine step (Andi, 2026-07-27: it costs a lot of tokens for little return, because a failure always ends in reading diff images). After deliberately changing or adding a screen, run `scripts/ui-snapshot.sh record ios|watch` once so the committed references stay current — that is text output only.

### Feel free to improve the app & process

When you notice it would be beneficial to change the Claude.md or structure of the Features.md file, feel free to do so. Don't do that for the sake of it, but when you notice that over a longer time some part of those files aren't helpful as they are, change it. Both files are versioned, so you cannot do much harm.