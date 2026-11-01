--- FIFO queue of named entries. A name can only be queued once at a time.
--   local q = Queue.new()
--   q:push({ name = "RedCAP-1", cost = 200 })
--   local head = q:peek()
--   q:pop()

local Queue = {}
Queue.__index = Queue

function Queue.new()
    return setmetatable({ first = 1, last = 0, items = {}, names = {} }, Queue)
end

--- Appends an entry. Returns false if an entry with that name is queued.
function Queue:push(entry)
    if self.names[entry.name] then
        return false
    end
    self.last = self.last + 1
    self.items[self.last] = entry
    self.names[entry.name] = true
    return true
end

--- First entry without removing it, or nil.
function Queue:peek()
    return self.items[self.first]
end

--- Removes and returns the first entry, or nil.
function Queue:pop()
    local entry = self.items[self.first]
    if entry == nil then
        return nil
    end
    self.items[self.first] = nil
    self.first = self.first + 1
    self.names[entry.name] = nil
    return entry
end

function Queue:contains(name)
    return self.names[name] == true
end

function Queue:size()
    return self.last - self.first + 1
end

--- Names in queue order, for status output.
function Queue:list()
    local list = {}
    for i = self.first, self.last do
        list[#list + 1] = self.items[i].name
    end
    return list
end

return Queue
