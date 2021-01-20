A short list of potential additions for the future:
- Add a add/removeComponent function
    - Given that an archetype-based design was opted for here, it may actually
    be more appropriate to not include this convenience wrapper. Users can still
    remove an entity and re-spawn it with its new set of components, and
    hopefully the friction of this operation will draw attention to the
    expensive copy happening under the surface here.
- Boolean combination queries
    - e.g. world.query(set(Position, Velocity));
- Create benchmarking harness
- Parallel iteration
    - legion/specs use rayon for easy parallel iteration
    - Explore fork/join model, worker queue model
    - What would the implications be for write access?
- Allow for separate capacities for init'ing arches, entity manager, etc
    - Potentially even on a function call basis, if you know that some objects
    will have very limited storage
- Batched entity spawning
