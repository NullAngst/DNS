-- Drop private addresses from public answers, like Unbound's private-address.
-- Loopback is included, so domains that resolve to 127.0.0.1 on purpose won't work.
private = newNMG()
private:addMasks({
  "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
  "172.16.0.0/12", "192.168.0.0/16",
  "::1/128", "::ffff:0:0/96", "fc00::/7", "fe80::/10"
})

function postresolve(dq)
  local records = dq:getRecords()
  local kept = {}
  local changed = false
  for _, r in ipairs(records) do
    if (r.type == pdns.A or r.type == pdns.AAAA) and private:match(newCA(r:getContent())) then
      changed = true
    else
      table.insert(kept, r)
    end
  end
  if changed then
    dq:setRecords(kept)
  end
  return changed
end
