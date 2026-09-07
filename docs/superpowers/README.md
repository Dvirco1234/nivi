# Design notes, kept as history

These are dated records of what was planned at the time. They stop at milestone
2d.1, dated 5 August 2026. Everything built after that, which is most of the app
as it stands, was never written up here.

**They are not a description of the app.** Some of what they describe changed
during implementation, and some was dropped. Reading them as current will mislead
you.

For what actually exists:

- [../architecture.md](../architecture.md) is how the code fits together today,
  including the places where the shipped code differs from these notes.
- [../state-of-the-project.md](../state-of-the-project.md) is what works, what is
  released and what is broken.
- [../decisions.md](../decisions.md) is what has been settled and why.

They are kept because the reasoning is often still useful. A spec explains why an
approach was picked over the alternatives, and that argument usually outlives the
details it was arguing about. The 2d and 2d.1 streaming notes in particular are
worth reading before changing anything in the streaming path, as long as you take
the architecture doc as the authority on what the code does now.
