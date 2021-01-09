TODO:
implement query
    probably need associated entity ids for this, def for below
    check out iterator from stdlib hashmap
implement remove (using entity id's?)



idea for calculating offset from start of a struct bundle to return:
comptime-only func in ArchetypeGen, before struct return
take index
return number
number is number of bytes offset from start of bundle, calc'd w/ inline for over
    type information
