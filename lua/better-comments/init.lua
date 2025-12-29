

local M = {}

local api = vim.api
local cmd = vim.api.nvim_create_autocmd
local treesitter = vim.treesitter
local opts = {
    tags = {
        {
            name = "TODO",
            fg = "white",
            bg = "#0a7aca",
            bold = true,
        },
        {
            name = "FIX",
            fg = "white",
            bg = "#f44747",
            bold = true,
        },
        {
            name = "WARNING",
            fg = "#FFA500",
            bold = false,
        },
        {
            name = "!",
            fg = "#f44747",
            bold = true,
        }

    },
}


M.setup = function(config)
    if config and config.tags then
        opts.tags = config.tags
    end

    local augroup = vim.api.nvim_create_augroup("better-comments", {clear = true})
    cmd({ 'BufWinEnter', 'BufFilePost', 'BufWritePost', 'TextChanged', 'TextChangedI'  }, {
        group = augroup,
        callback = function()
            local current_buffer = api.nvim_get_current_buf()
            local current_buffer_name = api.nvim_buf_get_name(current_buffer)
            if current_buffer_name == '' then
                return
            end
            local fileType = api.nvim_buf_get_option(current_buffer, "filetype")

            -- Some treesitter parsers don't use `comment` but because `treesitter.query.parse` is "strict", 
            -- it fails if any selector that's passed is not found, so we can't actually pass `[[(line_comment) @all (comment) @all]]` 
            -- because it is guaranteed to fail. so we make a LUT for hardcoded language parsers instead.
            local chosen_selector = ""
            local queries = {
                ["rust"] = "(line_comment) @all",
                ["default"] = "(comment) @all"
            }

            chosen_selector = queries[fileType] ~= nil and queries[fileType] or queries["default"]

            local success, parsed_query = pcall(function()
                return treesitter.query.parse(fileType, chosen_selector)
            end)
            if not success then
                return
            end
            local commentsTree = treesitter.query.parse(fileType, chosen_selector)

            -- FIX: Check if file has treesitter
            local root = Get_root(current_buffer, fileType)
            local comments = {}
            for _, node in commentsTree:iter_captures(root, current_buffer, 0, -1) do
                local range = { node:range() }
                table.insert(comments, {
                    line = range[1],
                    col_start = range[2],
                    finish = range[4],
                    text = vim.treesitter.get_node_text(node, current_buffer)
                })
            end

            if comments == {} then
                return
            end
            Create_hl(opts.tags)

            for id, comment in ipairs(comments) do
                for hl_id, hl in ipairs(opts.tags) do
                    -- local comment_chars = string.find(comment.text, "^%S+") or "" -- Can't do strikethrough on double-commented lines (I think) because tree-sitter sees the same line as two different comments; can't detect double comments properly, not spending time on this.

                    -- match whatever comment character sequence (assuming it's space separated), and then an optional space after 
                    -- it with the tag name. This prevents highlighting a comment unintentionally with a hyperlink or something similar
                    if string.match(comment.text, "^%S+%s*" .. hl.name) then
                        local ns_id = vim.api.nvim_create_namespace(hl.name)
                        if hl.virtual_text and hl.virtual_text ~= "" then
                            local v_opts = {
                                id = id,
                                virt_text = { { hl.virtual_text, "" } },
                                virt_text_pos = 'overlay',
                                virt_text_win_col = comment.finish + 2,
                            }

                            -- FIX: comment.line -> 0 in col
                            api.nvim_buf_set_extmark(current_buffer, ns_id, comment.line, 0, v_opts)
                        end

                        -- FIX: using for ns_id ns_id instead of 0 
                        -- so that when we clear the namespace the color also clear
                        vim.api.nvim_buf_add_highlight(current_buffer, ns_id, tostring(hl_id), comment.line,
                            comment.col_start,
                            comment.finish)
                    else
                        -- FIX: added else to delted extmark

                        -- TODO: THIS PART IS CALLED A LOT FIND A WAY TO NOT CHECK EVERY TIME
                        if hl.virtual_text ~= "" then
                            local ns_id = vim.api.nvim_create_namespace(hl.name)

                            -- FIX: clearing the namespace to delete the extmark and the color 
                            api.nvim_buf_clear_namespace(current_buffer, ns_id, comment.line, comment.line+1)
                        end
                    end
                end
            end
        end
    })
end

Get_root = function(bufnr, filetype)
    local parser = vim.treesitter.get_parser(bufnr, filetype, {})
    local tree = parser:parse()[1]
    return tree:root()
end

function Create_hl(list)
    for id, hl in ipairs(list) do
        vim.api.nvim_set_hl(0, tostring(id), {
            fg = hl.fg,
            bg = hl.bg,
            bold = hl.bold,
            underline = hl.underline,
        })
    end
end

return M
