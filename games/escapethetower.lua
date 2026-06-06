-- setup
pc.cls()
local running = true

-- command arrays
move = {"go", "move", "walk", "run", "jog", "mosey"}
direction = {"north", "n", "south", "s", "west", "w", "east", "e", "up", "u", "down", "d", "rise", "ascend", "descend"}
action = {"get", "take", "drop", "throw", "steal", "use", "open", "close", "eat", "drink", "hit", "attack", "beat"}

-- input string splitting based on space
function inputsplit (inputstr, sep)
   -- if sep is null, set it as space
   if sep == nil then
      sep = '%s'
   end
   -- define an array
   local t={}
   -- split string based on sep   
   for str in string.gmatch(inputstr, '([^'..sep..']+)') 
   do
      -- insert the substring in table
      table.insert(t, str)
   end
   -- return the array
   return t
end

-- command parsing
function cmd_parse (input)
    input_array = inputsplit(input)
    len = # (input_array)
    if ((len < 3) and (len > 0) and not (len == nil))
    then
        if (len == 1) then
            -- check for direction move command
            local cmd_move = false
            for _, cmd in pairs(direction) do
                -- check if input word is a direction
                if cmd == input_array[1] then
                    cmd_move = true
                    break
                end
        else
            if (not(cmd_move)) then
                for _, cmd in pairs(move) do
                    -- check if first input word is a move command
                    if cmd == input_array[1] then
                        cmd_move = true
                        break
                    end
                end
            end
            if (not (cmd_move)) then
                local cmd_action = false
                for _, cmd in pairs(action) do
                    -- check if first input word is an action command
                    if cmd == input_array[1] then
                        cmd_action = true
                        break
                    end
                end
            end
        end
    end
    if (cmd_move and cmd_action) then
        return -1
    elseif (not(cmd_move and cmd_action)) then
        return -1
    elseif (cmd_move) then
        local dir_valid = false
        local dir_index = nil
        local target = (len == 1) and input_array[1] or input_array[2]

        for i, dir in ipairs(direction) do
            -- check if direction is valid
            if (dir == target) then
                dir_valid = true
                dir_index = i
                break
            end
        end
        if (dir_valid) then
            if (not (dir_index == nil)) then
                if (dir_index < 3) then
                    return 8
                elseif (dir_index < 5) then
                    return 2
                elseif (dir_index < 7) then
                    return 4
                elseif (dir_index < 9) then
                    return 6
                elseif (dir_index < 11) then
                    return 7
                elseif (dir_index < 13) then
                    return 0
                elseif (dir_index < 15) then
                    return 7
                elseif (dir_index == 15) then
                    return 0
                end
            end
        end
    elseif (cmd_action) then
        return 5
    end
end


-- main loop
while running do
  local k = pc.getkey()
  if k == pc.KEY_ESC then
    running = false      -- exit the loop -> back to the launcher
  else
    -- handle input, update state, redraw
  end
end