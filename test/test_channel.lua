local test = require 'regress'
local ipc = require 'libipc'

test {
   -- status enums should be set on ipc.channel metatable
   statusEnumsSet = function()
      test.mustBeTrue(type(ipc.channel.OPEN) == 'number')
      test.mustBeTrue(type(ipc.channel.CLOSED) == 'number')
      test.mustBeTrue(type(ipc.channel.DRAINED) == 'number')
      test.mustBeTrue(ipc.channel.OPEN ~= ipc.channel.CLOSED)
      test.mustBeTrue(ipc.channel.CLOSED ~= ipc.channel.DRAINED)
      local expectedMethods = {
         'read', 'write', 'num_items', 'close', 'closed', 'drained'
      }
      local ch = ipc.channel()
      for _,x in ipairs(expectedMethods) do
         test.mustBeTrue(ch[x] ~= nil and type(ch[x]) == 'function')
      end
   end,

   -- it should be possible to open a channel, write something to it
   -- and read it back within the same thread.
   openReadWriteSameThread = function()
      local c = ipc.channel()
      local data = 10
      local status = c:write(data)
      test.mustBeTrue(status == ipc.channel.OPEN)
      test.mustBeTrue(c:num_items() == 1, 'number of items in channel is incorrect')
      local nonblocking = true
      local status, readData = c:read(nonblocking)
      test.mustBeTrue(status == ipc.channel.OPEN)
      test.mustBeTrue(c:num_items() == 0, 'number of items in channel is incorrect')
      test.mustBeTrue(
         data == readData,
         'data read from channel ('..readData..') does not match data written to channel ('..data..')'
      )
      -- writing nil should work
      local status = c:write(nil)
      test.mustBeTrue(status == ipc.channel.OPEN)
      test.mustBeTrue(c:num_items() == 1, 'number of items in channel is incorrect')
      local status, readData = c:read(nonblocking)
      test.mustBeTrue(status == ipc.channel.OPEN)
      test.mustBeTrue(c:num_items() == 0, 'number of items in channel is incorrect')
      test.mustBeTrue(
         nil == readData,
         'data read from channel does not match data written to channel (nil)'
      )
   end,

   -- it should be possible to write multiple values at once.
   openReadMultiWriteSameThread = function()
      local c = ipc.channel()
      local data = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,}
      local unpack = unpack or table.unpack
      local status = c:write(unpack(data))
      test.mustBeTrue(status == ipc.channel.OPEN)
      test.mustBeTrue(c:num_items() == 12, 'number of items in channel is incorrect')
      local nonblocking = true
      for i=1,#data do
         local status, readData = c:read(nonblocking)
         test.mustBeTrue(status == ipc.channel.OPEN)
         test.mustBeTrue(readData == i)
      end
   end,

   -- it should be possible to open a channel, write something to it
   -- and read it back in a different thread.
   openReadWriteDifferentThread = function()
      local c = ipc.channel()
      local items = {true, 10, 'foo'}
      local producer = ipc.map(1, function(c, items)
         local test = require 'regress'
         local ipc = require 'libipc'
         for _,x in ipairs(items) do
            local status = c:write(x)
            test.mustBeTrue(status == ipc.channel.OPEN)
         end
      end, c, items)
      producer:join()
      test.mustBeTrue(c:num_items() == #items, 'number of items in channel is incorrect')
      local consumer = ipc.map(1, function(c, items)
         local test = require 'regress'
         local ipc = require 'libipc'
         local nonblocking = false
         for i=1,#items do
            local status, item = c:read(nonblocking)
            test.mustBeTrue(status == ipc.channel.OPEN)
            test.mustBeTrue(
               items[i] == item,
               'item read from channel ('..tostring(item)..') does not match item written to channel ('..tostring(items[i])..')')
         end
      end, c, items)
      consumer:join()
   end,

   -- closing a channel should set closed/drained flags as expected
   flagsOnClosedChannel = function()
      -- empty channel
      local c = ipc.channel()
      c:close()
      c:close() -- repeated close()s are ok
      test.mustBeTrue(c:closed())
      test.mustBeTrue(c:drained())

      -- channel with stuffz
      local c = ipc.channel()
      local status = c:write('foo')
      test.mustBeTrue(status == ipc.channel.OPEN)
      test.mustBeTrue(c:num_items() == 1)
      c:close()
      local status = c:write('bar')
      test.mustBeTrue(status == ipc.channel.CLOSED)
      test.mustBeTrue(c:num_items() == 1)
      local status, item = c:read()
      test.mustBeTrue(status == ipc.channel.CLOSED)
      test.mustBeTrue(item == 'foo')
      local status, item = c:read()
      test.mustBeTrue(status == ipc.channel.DRAINED)
      test.mustBeTrue(item == nil)
      local status = c:write('bar')
      test.mustBeTrue(status == ipc.channel.DRAINED)
      test.mustBeTrue(c:num_items() == 0)
   end,

   -- it should be possible to send a channel within another channel to another thread.
   sendChannelInChannel = function()
      local ca = ipc.channel()
      local cb = ipc.channel()
      local items = {true, 10, 'foo'}
      ca:write(cb)
      for _,x in ipairs(items) do
         ca:write(x)
      end
      ca:write('STOP')
      test.mustBeTrue(cb:num_items() == 0, 'number of items in channel is incorrect')
      test.mustBeTrue(ca:num_items() == #items+2, 'number of items in channel is incorrect')
      local echo = ipc.map(1, function(ca)
         local test = require 'regress'
         local ipc = require 'libipc'
         local nonblocking = false
         local status, cb = ca:read(nonblocking)
         test.mustBeTrue(status == ipc.channel.OPEN)
         while true do
            local status, input = ca:read(nonblocking)
            test.mustBeTrue(status == ipc.channel.OPEN)
            if input == 'STOP' then
               break
            else
               cb:write(input)
            end
         end
      end, ca)
      echo:join()
      test.mustBeTrue(ca:num_items() == 0, 'number of items in channel is incorrect')
      test.mustBeTrue(cb:num_items() == #items, 'number of items in channel is incorrect')
      for i=1,#items do
         local nonblocking = true
         local status, item = cb:read(nonblocking)
         test.mustBeTrue(status == ipc.channel.OPEN)
         test.mustBeTrue(
            items[i] == item,
            'item read from channel ('..tostring(item)..') does not match item written to channel ('..tostring(items[i])..')')
      end
   end,

   channelClosedWhileProducersWaiting = function()
      local c = ipc.channel()
      local workers = ipc.map(10, function(c)
         local test = require 'regress'
         local ipc = require 'libipc'
         while true do
            local status, data = c:read(false)
            if status == ipc.channel.DRAINED then
               break
            else
               test.mustBeTrue(false, 'should not put anything on channel')
            end
         end
      end, c)
      sys.sleep(5) -- allow workers to start and block on read
      c:close()
      -- this should not block indefinitely. workers should exit on
      -- drained channel.
      workers:join()
   end,

   -- it should be possible to use channels as a workqueue
   channelsAsWorkQueue = function()
      local toWorkqueue = ipc.channel() -- used to send items to workers
      local fromWorkers = ipc.channel() -- used to receive results back from workers
      local nItems = 100
      local items = {}
      for i = 1,nItems do
         table.insert(items, i)
      end
      -- multiple threads can send items to workers
      local nWorkloadGenerators = 10
      local workloadGenerators = ipc.map(nWorkloadGenerators, function(toWorkqueue, items)
         local test = require 'regress'
         local ipc = require 'libipc'
         for _,x in ipairs(items) do
            local status = toWorkqueue:write(x)
            -- workload generators expect that the workqueue remains
            -- open until they have finished enqueueing all the work
            -- items. This does not have to be the case - they could
            -- just stop enqueuing items when they see that the
            -- workqueue has been closed.
            test.mustBeTrue(status == ipc.channel.OPEN)
         end
      end, toWorkqueue, items)
      -- multiple threads can act as workers
      local nWorkers = 5
      local workers = ipc.map(nWorkers, function(toWorkqueue, fromWorkers)
         local test = require 'regress'
         local ipc = require 'libipc'
         while true do
            local nonblocking = false -- use blocking reads to avoid busy-waiting
            local status, item = toWorkqueue:read(nonblocking)
            -- workers are pretty dumb. They keep reading items from
            -- the workqueue and writing the results to the results
            -- queue until they either find that the workqueue has
            -- been drained or the results queue has been closed. No
            -- need for control signals.
            if status == ipc.channel.DRAINED then
               print('worker finishing: toWorkqueue channel drained')
               break
            end
            local status = fromWorkers:write(item)
            if status ~= ipc.channel.OPEN then
               print('worker finishing: fromWorkers channel closed')
               break
            end
         end
      end, toWorkqueue, fromWorkers)
      -- Ensure that workload generators have finished populating
      -- workqueue before closing it. This is because we want all 1000
      -- items to be in the workqueue. One could just close the
      -- workqueue at any point to stop the workload generator
      -- threads' behavior, e.g. to stop enqueuing work and exit.
      workloadGenerators:join()
      -- Close the workqueue so that the worker threads can drain the
      -- workqueue and exit.
      toWorkqueue:close()
      -- Wait for workers to finish so that we can check correctness.
      workers:join()
      test.mustBeTrue(toWorkqueue:drained())
      test.mustBeTrue(toWorkqueue:num_items() == 0)
      local nReturnedItems = nItems * nWorkloadGenerators
      test.mustBeTrue(fromWorkers:num_items() == nReturnedItems)
      fromWorkers:close()
      local returnedItems = {}
      while true do
         local nonblocking = true
         local status, item = fromWorkers:read(nonblocking)
         if status == ipc.channel.DRAINED then
            break
         else
            table.insert(returnedItems, item)
         end
      end
      test.mustBeTrue(fromWorkers:closed())
      test.mustBeTrue(fromWorkers:drained())
      test.mustBeTrue(fromWorkers:num_items() == 0)
      test.mustBeTrue(#returnedItems == nReturnedItems)
      local counts = {}
      for _,x in ipairs(returnedItems) do
         counts[x] = (counts[x] or 0) + 1
      end
      for i = 1,nItems do
         test.mustBeTrue(counts[i] == nWorkloadGenerators)
      end
   end,

   pingPong = function()
      -- 1:1 synchronization between two threads
      local c = ipc.channel()
      local output = ipc.channel()
      local npings = 10
      local pinger = ipc.map(1, function(c, npings)
         for i = 1,npings do
            c:write('ping?')
         end
         c:close()
      end, c, npings)
      local ponger = ipc.map(1, function(c, o)
         local ipc = require 'libipc'
         while true do
            local nonblocking = false
            local status, item = c:read(nonblocking)
            if status == ipc.channel.DRAINED then
               break
            elseif item == 'ping?' then
               o:write('pong!')
            end
         end
      end, c, output)
      pinger:join()
      ponger:join()
      output:close()
      local outputList = {}
      while true do
         local nonblocking = true
         local status, item = output:read(nonblocking)
         if status == ipc.channel.DRAINED then
            break
         else
            table.insert(outputList, item)
         end
      end
      test.mustBeTrue(#outputList == npings)
      for _,x in ipairs(outputList) do
         test.mustBeTrue(x == 'pong!')
      end
   end,
}
