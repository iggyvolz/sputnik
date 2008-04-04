---------------------------------------------------------------------------------------------------
-- Defines a "Smart Repository": a collection of versium nodes with inheritance.
---------------------------------------------------------------------------------------------------

module(..., package.seeall)

require("versium")
require("saci.node")
local Repository = {}
local Repository_mt = {__metatable={}, __index=Repository}

---------------------------------------------------------------------------------------------------
-- Creates a new instance of Repository.
-- 
-- @param config         the bootstrapping config table.
-- @return               an instance of "Repository".
---------------------------------------------------------------------------------------------------
function new(config)

   local repo = setmetatable({}, Repository_mt)
   repo.config = config
   local versium_params = config.VERSIUM_PARAMS
   repo.versium = versium.new{
       storage = config.VERSIUM_STORAGE_MODULE or "versium.storage.simple",
       params = config.VERSIUM_PARAMS
   }

   return repo
end

-----------------------------------------------------------------------------
-- Returns true if the node exists and false otherwise.
-- 
-- @param id             an id of an node.
-- @return               true or false.
-----------------------------------------------------------------------------

function Repository:node_exists(id)
   return self.versium:node_exists(id)
end


-----------------------------------------------------------------------------
-- Inflates a versium node, turning it into a Lua table.
--
-- @param node           The node to be "inflated" (represented as a versium
--                       node object).
-- @return               A table representing the fields of the node, with
--                       the metadata and the string representation pushed
--                       into the metatable.
-----------------------------------------------------------------------------
function Repository:inflate(node)

   local object = saci.sandbox.new():do_lua(node.data)
   assert(object, "the inflator should give us a table unless something went very wrong")
   local meta = {
      _version = {
         id        = node.version,
         timestamp = node.timestamp,
         author    = node.author,
         comment   = node.comment,
         extra     = node.extra,
      },
      _raw = node.data,
      _id  = node.id,
   }
   meta.__index = meta
   setmetatable(object, meta)
   return object
end

-----------------------------------------------------------------------------
-- Turns a node represented as a Lua table into a string representation which
-- could later be inflated again.
--
-- @param node           A versium node as a table.
-- @return               The string representation of the versium node.
-----------------------------------------------------------------------------
function Repository:deflate(node)
   local buffer = ""
   for k,v in pairs(node) do
      if k~="__index" then
         buffer = buffer.."\n "..k.."= "..string.format("%q", tostring(v))
      end
   end
   return buffer
end


---------------------------------------------------------------------------------------------------
-- Retrieves a node transformed it into a "smart node".  This method overrides versium's get_node().
--
-- @param id             the id of the desired node.
-- @param version        the desired version of the node (defaults to latest).
-- @return               (1) a table representing the fields of the node, with the metadata and the 
--                       string representatoin pushed into the metatable.
--                       (2) the boolean value 'true' if the node returned was a stub, otherwise
--                       nil.
---------------------------------------------------------------------------------------------------

--require"sputnik.installer.initial_pages"

function Repository:get_node(id, version, mode)
   assert(id)
   if self.logger then 
      self.logger:debug(id)
      self.logger:debug(version)
   end
   local versium_node = self.versium:get_node(id, version) 
   local stub
   if not versium_node then
      local status, page_module = pcall(require, "sputnik.node_defaults."..id)
      if status then
         local default = self:deflate(page_module.NODE)
		 -- Only create the default node if the CREATE_DEFAULT flag is set
         if page_module.CREATE_DEFAULT then
             self.versium:save_version(id, default, "Sputnik", "the default version")
             versium_node = self.versium:get_node(id, version)
         else
             -- Otherwise, create a stub and set the data
             -- This page won't be saved until it's explicitly edited and saved
             versium_node = self.versium:get_stub(id)
             versium_node.data = default
         end
      else 
         versium_node = self.versium:get_stub(id)
		 stub = true
      end
   end
   versium_node = self:inflate(versium_node)
   assert(versium_node._version)
   return saci.node.new(versium_node, self, self.config.ROOT_PROTOTYPE, mode), stub
end

---------------------------------------------------------------------------------------------------
-- Saves a node.
--
-- @param node           the node to be saved.
-- @param author         the .user name associated with the change (required).
-- @param comment        a comment associated with this change (optional).
-- @param extra          extra params (optional).
-- @return               nothing
---------------------------------------------------------------------------------------------------
function Repository:save_node(node, author, comment, extra)
   assert(node._id)
   self.versium:save_version(node._id, self:deflate(node._vnode), author, comment, extra)
end

---------------------------------------------------------------------------------------------------
-- Returns the history of edits to the node.
--
-- @param id             the id of the node.
-- @param prefix         an optional date prefix (e.g., "2007-12").
-- @return               history as a table.
---------------------------------------------------------------------------------------------------
function Repository:get_node_history(id, prefix)
   assert(id)
   local versium_history = self.versium:get_node_history(id, prefix)
   for i,v in ipairs(versium_history) do
      v.get_node = function() self:get_node(id, v.version) end
   end
   return versium_history
end
