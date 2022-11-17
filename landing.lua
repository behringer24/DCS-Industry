-- Handler for landed planes by puni5her

if (landing ~= nil) then return 0 end
landing = {}

landing.autoDestroyPlanes = {}

function landing.autoDestroy(name)
    landing.autoDestroyPlanes[name] = true
end

landing.handler = {}
    function landing.handler:onEvent(event)
        if (event.id == 19) then
            local name = event.initiator:getName()
            if (landing.autoDestroyPlanes[name]) then
                _unit = Unit.getByName(name)
                _unit:destroy()
                trigger.action.outText(name .. ' got auto detroyed', 60)
            else
                trigger.action.setUserFlag(name .. '_landed', true)
            end
        end
    end

world.addEventHandler(landing.handler)
