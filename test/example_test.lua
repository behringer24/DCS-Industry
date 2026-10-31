-- the shipped example configuration must be valid

dcs.start(industryFixture.mission())
loadBundle()

local examplePath = __TARMAC.file:gsub("test[/\\]example_test%.lua$", "examples/init.lua")
dofile(examplePath)

test("the example configuration starts Industry without unknown keys", function()
    expect.equal(industry.config.production.perFactory, 33)
    expect.equal(industry.config.tickets.start, 150)
    for _, line in ipairs(dcs.logs) do
        expect.falsy(line:find("unknown configuration key", 1, true), line)
    end
end)
