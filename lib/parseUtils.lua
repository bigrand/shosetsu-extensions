-- {"ver":"1.0.1","author":"bigrand"}

--[[

   A collection of functions for parsing and formatting plain text and HTML.

    Functions:
        • string(text: string)
            - Normalizes line endings.
            - parserTrims lines and collapses extra spaces.
            - Handles divider lines, dialogue breaks, punctuation, list items, and title markers.

        • HTML(text: string)
            - Removes extra whitespace between HTML tags.
            - Converts <br> and </p> tags to newlines.
            - Strips all remaining HTML tags.

        • HTMLSingle(text: string)
            - Converts <br> and </p> tags to newlines.
            - Strips all remaining HTML tags.

        • trim(s: string)
            - A helper function that removes leading and trailing whitespace from a string.

    Usage:
        Call the function that matches your input type:
        - For plain text:       string(text: string)
            Note: This parser applies general normalization rules and does not interpret context,
            so the output probably will not reflect the writer’s intent or have perfect formatting.
        - For multi-line HTML:  HTML(text: string)
        - For single-line HTML: HTMLSingle(text: string)
        - For trimming: trim(s: string)
        Output is always a string.

]]

local function string(text)
	text = text:gsub("\r\n", "\n")
	text = text:gsub("\r", "\n")

	local lines = {}
	for line in text:gmatch("([^\n]*)\n?") do
		table.insert(lines, line:match("^%s*(.-)%s*$"))
	end
	text = table.concat(lines, "\n")

	text = text:gsub("[ \t]+", " ")

	text = text:gsub("([%*%!%-][%*%!%-][%*%!%-][%*%!%-]*)%s*\n", "%1\n\n")
	text = text:gsub("([%*%!%-][%*%!%-][%*%!%-][%*%!%-]*)%s*$", "%1\n\n")

	text = text:gsub("([%*%!%-][%*%!%-][%*%!%-][%*%!%-]*)(%s+)(%S)", function(div, spaces, nextChar)
		return div .. "\n\n" .. spaces .. nextChar
	end)

	text = text:gsub('([”"])%s+([“"])', "%1\n%2")

	text = text:gsub('([%.%!%?])(%s+)([^”"])', function(punct, spaces, nextChar)
		return punct .. "\n\n" .. nextChar
	end)

	text = text:gsub("(%S:)%s+", "%1\n")
	text = text:gsub("%s*%-%s+", "\n- ")
	text = text:gsub("(%S)(\n)(%-)", "%1%2%3")
	text = text:gsub(":\n%-", ":\n-")
	text = text:gsub("(\n\n)\n+", "%1")
	text = text:gsub("【", "["):gsub("】", "]")

	return text
end

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function HTML(text)
	text = text:gsub(">%s+<", "><")

	local brTag = "%s*<[Bb][Rr]%s*(/?)%s*>%s*"

	local pattern2 = brTag .. brTag .. "(" .. brTag .. ")*"
	text = text:gsub(pattern2, "[[BRBR]]")

	text = text:gsub(brTag, "\n")
	text = text:gsub("</[Pp]>", "\n\n")
	text = text:gsub("<[^>]+>", "")
	text = text:gsub("%[%[BRBR%]%]", "\n\n")

	local lines = {}

	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, trim(line))
	end

	text = table.concat(lines, "\n")
	text = trim(text)

	return text
end

local function HTMLSingle(text)
	text = text:gsub("<[bB][rR]%s*/?>", "\n")
	text = text:gsub("</[pP]>", "\n\n")
	text = text:gsub("<[^>]+>", "")
  	text = text .. "\n"

	local lines = {}
	text = text:gsub("(.-)\n", function(line)
	  local parserTrimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
	  table.insert(lines, parserTrimmed)
	end)

	local result = table.concat(lines, "\n")
	return result:gsub("^%s+", ""):gsub("%s+$", "")
end

return {
    string = string,
    trim = trim,
    HTML = HTML,
    HTMLSingle = HTMLSingle 
}