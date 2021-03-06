" tag source for unite.vim
" Version:     0.1.0
" Last Change: 09-Apr-2014.
" Author:      tsukkee <takayuki0510 at gmail.com>
"              thinca <thinca+vim@gmail.com>
"              Shougo <ShougoMatsu at gmail.com>
" Licence:     The MIT License {{{
"     Permission is hereby granted, free of charge, to any person obtaining a copy
"     of this software and associated documentation files (the "Software"), to deal
"     in the Software without restriction, including without limitation the rights
"     to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
"     copies of the Software, and to permit persons to whom the Software is
"     furnished to do so, subject to the following conditions:
"
"     The above copyright notice and this permission notice shall be included in
"     all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
"     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
"     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
"     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
"     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
"     OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
"     THE SOFTWARE.
" }}}

" define source
function! unite#sources#tag#define()
    return [s:source, s:source_files, s:source_include]
endfunction

let g:unite_source_tag_max_name_length =
    \ get(g:, 'unite_source_tag_max_name_length', 25)
let g:unite_source_tag_max_fname_length =
    \ get(g:, 'unite_source_tag_max_fname_length', 20)
let g:unite_source_tag_max_candidate_length =
    \ get(g:, 'unite_source_tag_max_candidate_length', 200)
let g:unite_source_tag_filter_mode =
    \ get(g:, 'unite_source_tag_filter_mode', 'aoi')

" When enabled, use multi-byte aware string truncate method
let g:unite_source_tag_strict_truncate_string =
    \ get(g:, 'unite_source_tag_strict_truncate_string', 1)

let g:unite_source_tag_show_location =
    \ get(g:, 'unite_source_tag_show_location', 1)

let g:unite_source_tag_show_fname =
    \ get(g:, 'unite_source_tag_show_fname', 1)

" cache
let s:tagfile_cache = {}
let s:input_cache = {}

" source
let s:source = {
\   'name': 'tag',
\   'description': 'candidates from tag file',
\   'max_candidates': g:unite_source_tag_max_candidate_length,
\   'action_table': {},
\   'hooks': {},
\   'syntax': 'uniteSource__Tag',
\}

function! s:source.hooks.on_syntax(args, context)
  syntax match uniteSource__Tag_File /  @.\{-}  /ms=s+2,me=e-2
              \ containedin=uniteSource__Tag contained
              \ nextgroup=uniteSource__Tag_Pat,uniteSource__Tag_Line skipwhite
  syntax match uniteSource__Tag_Pat /pat:.\{-}\ze\s*$/ contained
  syntax match uniteSource__Tag_Line /line:.\{-}\ze\s*$/ contained
  highlight default link uniteSource__Tag_File Type
  highlight default link uniteSource__Tag_Pat Comment
  highlight default link uniteSource__Tag_Line Constant
  if has('conceal')
      syntax match uniteSource__Tag_Ignore /pat:/
                  \ containedin=uniteSource__Tag_Pat conceal
  else
      syntax match uniteSource__Tag_Ignore /pat:/
                  \ containedin=uniteSource__Tag_Pat
      highlight default link uniteSource__Tag_Ignore Ignore
  endif
endfunction

function! s:source.hooks.on_init(args, context)
    let a:context.source__tagfiles = tagfiles()
    let a:context.source__name = 'tag'
endfunction

function! s:source.gather_candidates(args, context)
    let a:context.source__continuation = []
    if a:context.input != ''
        return s:taglist_filter(a:context.input)
    endif

    let result = []
    for tagfile in a:context.source__tagfiles
        let tagdata = s:get_tagdata(tagfile)
        if empty(tagdata)
            continue
        endif
        let result += tagdata.tags
        if has_key(tagdata, 'cont')
            call add(a:context.source__continuation, tagdata)
        endif
    endfor

    let a:context.source__cont_number = 1
    let a:context.source__cont_max = len(a:context.source__continuation)

    return s:pre_filter(result, a:args)
endfunction

function! s:source.async_gather_candidates(args, context)
    if empty(a:context.source__continuation)
        let a:context.is_async = 0
        call unite#print_message(
        \    printf('[%s] Caching Done!', a:context.source__name))
        return []
    endif

    let result = []
    let tagdata = a:context.source__continuation[0]
    if !has_key(tagdata, 'cont')
        return []
    endif

    if a:context.immediately
        while !empty(tagdata.cont.lines)
            let result += s:next(tagdata, remove(tagdata.cont.lines, 0), self.name)
        endwhile
    elseif has('reltime') && has('float')
        let time = reltime()
        while str2float(reltimestr(reltime(time))) < 1.0
        \       && !empty(tagdata.cont.lines)
            let result += s:next(tagdata, remove(tagdata.cont.lines, 0), self.name)
        endwhile
    else
        let i = 1000
        while 0 < i && !empty(tagdata.cont.lines)
            let result += s:next(tagdata, remove(tagdata.cont.lines, 0), self.name)
            let i -= 1
        endwhile
    endif

    call unite#clear_message()

    let len = tagdata.cont.lnum
    let progress = (len - len(tagdata.cont.lines)) * 100 / len
    call unite#print_message(
                \    printf('[%s] [%2d/%2d] Caching of "%s"...%d%%',
                \           a:context.source__name,
                \           a:context.source__cont_number, a:context.source__cont_max,
                \           tagdata.cont.tagfile, progress))

    if empty(tagdata.cont.lines)
        call remove(tagdata, 'cont')
        call remove(a:context.source__continuation, 0)
        let a:context.source__cont_number += 1
    endif

    return s:pre_filter(result, a:args)
endfunction


" source tag/file
let s:source_files = {
\   'name': 'tag/file',
\   'description': 'candidates from files contained in tag file',
\   'action_table': {},
\   'hooks': {'on_init': s:source.hooks.on_init},
\   'async_gather_candidates': s:source.async_gather_candidates,
\}

function! s:source_files.gather_candidates(args, context)
    let a:context.source__continuation = []
    let files = {}
    for tagfile in a:context.source__tagfiles
        let tagdata = s:get_tagdata(tagfile)
        if empty(tagdata)
            continue
        endif
        call extend(files, tagdata.files)
        if has_key(tagdata, 'cont')
            call add(a:context.source__continuation, tagdata)
        endif
    endfor

    let a:context.source__cont_number = 1
    let a:context.source__cont_max = len(a:context.source__continuation)

    return map(sort(keys(files)), 'files[v:val]')
endfunction


" source tag/include
let s:source_include = deepcopy(s:source)
let s:source_include.name = 'tag/include'
let s:source_include.description =
            \ 'candidates from files contained in include tag file'
let s:source_include.max_candidates = 0

function! s:source_include.hooks.on_init(args, context)
    if exists('*neocomplete#sources#include#get_include_files')
        let a:context.source__tagfiles = filter(map(
                    \ copy(neocomplete#sources#include#get_include_files(bufnr('%'))),
                    \ "neocomplete#cache#encode_name('tags_output', v:val)"),
                    \ 'filereadable(v:val)')
    elseif exists('*neocomplcache#sources#include_complete#get_include_files')
        let a:context.source__tagfiles = filter(map(
                    \ copy(neocomplcache#sources#include_complete#get_include_files(bufnr('%'))),
                    \ "neocomplcache#cache#encode_name('tags_output', v:val)"),
                    \ 'filereadable(v:val)')
    else
        let a:context.source__tagfiles = []
    endif
    let a:context.source__name = 'tag/include'
endfunction

function! s:source_include.gather_candidates(args, context)
    if empty(a:context.source__tagfiles)
        call unite#print_message(
        \    printf('[%s] Nothing include files.', a:context.source__name))
    endif

    let a:context.source__continuation = []
    let result = []
    for tagfile in a:context.source__tagfiles
        let tagdata = s:get_tagdata(tagfile)
        if empty(tagdata)
            continue
        endif
        let result += tagdata.tags
        if has_key(tagdata, 'cont')
            call add(a:context.source__continuation, tagdata)
        endif
    endfor

    let a:context.source__cont_number = 1
    let a:context.source__cont_max = len(a:context.source__continuation)

    return s:pre_filter(result, a:args)
endfunction


function! s:pre_filter(result, args)
    if !empty(a:args)
        let arg = a:args[0]
        if arg !=# ''
            if arg ==# '/'
                let pat = arg[1 : ]
                call filter(a:result, 'v:val.word =~? pat')
            else
                call filter(a:result, 'v:val.word == arg')
            endif
        endif
    endif
    return a:result
endfunction

function! s:get_tagdata(tagfile)
    let tagfile = fnamemodify(a:tagfile, ':p')
    if !filereadable(tagfile)
        return {}
    endif
    if !has_key(s:tagfile_cache, tagfile) ||
                \ s:tagfile_cache[tagfile].time != getftime(tagfile)
        let lines = readfile(tagfile)
        let s:tagfile_cache[tagfile] = {
        \   'time': getftime(tagfile),
        \   'tags': [],
        \   'files': {},
        \   'cont': {
        \     'lines': lines,
        \     'lnum': len(lines),
        \     'basedir': fnamemodify(tagfile, ':p:h'),
        \     'encoding': '',
        \     'tagfile': tagfile,
        \   },
        \}
    endif
    return s:tagfile_cache[tagfile]
endfunction

function! s:taglist_filter(input)
    if g:unite_source_tag_filter_mode == ''
        let taglist = s:taglist_filter_normal(a:input)
    elseif g:unite_source_tag_filter_mode == 'aoi'
        let taglist = s:taglist_filter_aoi(a:input)
        let taglist = s:add_input_taglist(a:input, taglist)
    endif
    return taglist
endfunction

function! s:add_input_taglist(input, taglist)
    for tag in a:taglist
        let tag.word = a:input . tag.word
    endfor
    return a:taglist
endfunction

function! s:taglist_filter_normal(input)
    let key = string(tagfiles()).a:input
    if has_key(s:input_cache, key)
        return s:input_cache[key]
    endif

    let unite   = unite#get_current_unite()
    let context = unite.context
    let format_name = (context.multi_line==1 && g:unite_source_tag_max_name_length!=0)? "%s\n":"%s "
    let format_file = (context.multi_line==1 && g:unite_source_tag_max_fname_length!=0)? "%s\n":"%s "
    let format_pat  = "%s"
    let format = format_name . format_file . format_pat

    let taglist = map(taglist(a:input), "{
    \   'word':    v:val.name,
    \   'abbr':    printf(format,
    \                  s:truncate(v:val.name,
    \                     g:unite_source_tag_max_name_length, 15, '..', 0),
    \                  s:truncate('@'.fnamemodify(
    \                     v:val.filename, ':.'),
    \                     g:unite_source_tag_max_fname_length, 10, '..', 0),
    \                  'pat:' .  matchstr(v:val.cmd,
    \                         '^[?/]\\^\\?\\zs.\\{-1,}\\ze\\$\\?[?/]$')
    \                  ),
    \   'kind':    'jump_list',
    \   'action__path':    unite#util#substitute_path_separator(
    \                   v:val.filename),
    \   'action__tagname': v:val.name,
    \   'source__cmd': v:val.cmd,
    \}")


    " Set search pattern.
    for tag in taglist
        let cmd = tag.source__cmd
        if cmd =~ '^\d\+$'
            let linenr = cmd - 0
            let tag.action__line = linenr
        else
            " remove / or ? at the head and the end
            let pattern = matchstr(cmd, '^\([/?]\)\?\zs.*\ze\1$')
            " unescape /
            let pattern = substitute(pattern, '\\\/', '/', 'g')
            " use 'nomagic'
            let pattern = '\M' . pattern

            let tag.action__pattern = pattern
        endif
    endfor
    let s:input_cache[key] = taglist
    return taglist
endfunction

function! s:taglist_filter_aoi(input)
    let unite   = unite#get_current_unite()
    let context = unite.context
    let format_name = (context.multi_line==1 && g:unite_source_tag_max_name_length!=0)? "%s\n":"%s "
    let format_file = (context.multi_line==1 && g:unite_source_tag_max_fname_length!=0)? "%s\n":"%s "
    let format_pat  = "%s"
    let format = format_name . format_file . format_pat

    let input = s:convert_input(a:input) . '$'

    let current_file = expand('%:p')
    let key = string(tagfiles()).current_file.input
    if has_key(s:input_cache, key)
        return s:input_cache[key]
    endif

    let taglist = map(taglist(input), "{
    \   'word':    v:val.name,
    \   'abbr':    printf(format,
    \                  s:truncate(v:val.name,
    \                     g:unite_source_tag_max_name_length, 15, '..', 0),
    \                  s:truncate('@'. v:val.filename,
    \                     g:unite_source_tag_max_fname_length, 10, '..', 0),
    \                  'pat:' .  matchstr(v:val.cmd,
    \                         '^[?/]\\^\\?\\zs.\\{-1,}\\ze\\$\\?[?/]$')
    \                  ),
    \   'kind':    'jump_list',
    \   'action__path':    unite#util#substitute_path_separator(
    \                   v:val.filename),
    \   'action__tagname': v:val.name,
    \   'source__cmd': v:val.cmd,
    \}")

    " Set aoi search pattern.
    let taglist_filtered = []
    let filter_words = s:get_filter_word(a:input)

    for tag in taglist
        let is_all_filter_pass = 1
        for word in filter_words
            let match_filter = match(tag.abbr, word)
            if match_filter == -1
                let is_all_filter_pass = 0
                break
            endif
        endfor
        if is_all_filter_pass != 1
            continue
        endif

        let cmd = tag.source__cmd
        if cmd =~ '^\d\+$'
            let linenr = cmd - 0
            let tag.action__line = linenr
        else
            " remove / or ? at the head and the end
            let pattern = matchstr(cmd, '^\([/?]\)\?\zs.*\ze\1$')
            " unescape /
            let pattern = substitute(pattern, '\\\/', '/', 'g')
            " use 'nomagic'
            let pattern = '\M' . pattern

            let tag.action__pattern = pattern
        endif
        let taglist_filtered = insert(taglist_filtered, tag)
    endfor
    let s:input_cache[key] = taglist_filtered

    return taglist_filtered
endfunction

function! s:get_filter_word(input)
    let filename = expand("%:p")
    let pathes = split(filename, '/')
    let filetype = s:get_filetype(pathes)
    let tagtype = s:get_tagtype(a:input)

    let filter_words = []
    if filetype ==# 'action'
        let filter_words = s:get_filter_word_action(tagtype)
    endif

    if filetype ==# 'processor'
        let filter_words = s:get_filter_word_processor(tagtype)
    endif

    if filetype ==# 'module'
        let filter_words = s:get_filter_word_module(tagtype)
    endif

    let line = getline('.')
    let count_arrow = s:count_needle(line, '->')
    if count_arrow == 1
        "this->method()の形なので自クラス名でtaglistの結果を間引く
        let path = expand('%:p')
        let match_from_list = ['act', 'LegacyModule', 'Processor', 'Module']
        let match_name = ''
        for match_word in match_from_list
            let match_name = matchstr(path, match_word . '\zs/.*.', 'g')
            if len(match_name) > 0
                break
            endif
        endfor
        let filter_words = insert(filter_words, match_name)
    endif

    return filter_words
endfunction

function! s:get_filter_word_action(tagtype)
    let words = []
    return words
endfunction

function! s:count_needle(string, needle)
    let max = strlen(a:string)
    let counter = 0
    let index = 0
    let index = match(a:string, a:needle, index)
    while index != -1
        let counter = counter + 1
        let index = match(a:string, a:needle, index + 1)
    endwhile
    return counter
endfunction

function! s:get_filter_word_processor(tagtype)
    let words = []
    let line = getline('.')
    let pathes = split(line, '->')
    let class_path = ''
    let is_legacy = match(line, 'legacy_module')
    let class_path_index = (is_legacy == -1)? 1:2

    if len(pathes) >= 3
        let class_part      = pathes[class_path_index]
        let class_path_list = split(class_part, '_')
        let class_path_camelized = []
        for class_path in class_path_list
            let class_path_camelized = insert(class_path_camelized, s:to_camel(class_path), len(class_path_camelized))
        endfor
        let class_name = join(class_path_camelized, '/')
        if is_legacy == -1
            let class_path = 'Module/' . class_name . '.php'
        else
            let class_path = 'LegacyModule/' . class_name . '.php'
        endif
    endif

    if a:tagtype ==# 'method'
        let words = insert(words, class_path)
    endif

    if a:tagtype ==# 'class'
        let words = insert(words, class_path)
    endif

    return words
endfunction

function! s:get_filter_word_module(tagtype)
    let words            = []
    let line             = getline('.')
    let is_data          = match(line, '->data->')
    let is_legacy        = match(line, '->legacy_module->')
    let is_module        = match(line, '->module->')

    let class_path       = ''
    let pathes           = split(line, '->')

    if len(pathes) >= 4
        let class_part      = pathes[2]
        let class_path_list = split(class_part, '_')
        let class_path_camelized = []
        for class_path in class_path_list
            let class_path_camelized = insert(class_path_camelized, s:to_camel(class_path), len(class_path_camelized))
        endfor
        let class_name = join(class_path_camelized, '/')
        if is_data != -1
            let class_path = class_name . '.php'
        elseif is_legacy != -1
            let class_path = 'LegacyModule/' . class_name . '.php'
        elseif is_module != -1
            let class_path = 'Module/' . class_name . '.php'
        endif
    endif

    if a:tagtype ==# 'method'
        if is_data != -1
            let words = insert(words, 'Cascade/\(DataFormat\|Gateway\)/' . class_path)
        else
            let words = insert(words, class_path)
        endif
    endif

    if a:tagtype ==# 'class'
        if is_data != -1
            let words = insert(words, 'Cascade/\(DataFormat\|Gateway\)/' . class_path)
        else
            let words = insert(words, class_path)
        endif
    endif

    return words
endfunction

function! s:get_tagtype(input)
    let line = getline('.')

    let match_method = match(line, a:input . "(")
    if match_method != -1
        return 'method'
    endif

    let match_class  = match(line, '->' . a:input . '->')
    if match_class != -1
        return 'class'
    endif

    return 'default'
endfunction

function! s:get_filetype(pathes)
    let match_act       = 0
    let match_app       = 0
    let match_aoi       = 0
    let match_frontend  = 0
    let match_service   = 0
    let match_processor = 0
    let match_module    = 0

    for path in a:pathes
        let act_index       = match(path, '\cact')
        let app_index       = match(path, '\capp')
        let aoi_index       = match(path, '\caoi')
        let frontend_index  = match(path, '\cfrontend')
        let service_index   = match(path, '\cservice')
        let processor_index = match(path, '\cprocessor')
        let module_index    = match(path, '\cmodule')
        if act_index != -1
            let match_act = 1
        endif
        if app_index != -1
            let match_app = 1
        endif
        if aoi_index != -1
            let match_aoi = 1
        endif
        if frontend_index != -1
            let match_frontend = 1
        endif
        if service_index != -1
            let match_service = 1
        endif
        if processor_index != -1
            let match_processor = 1
        endif
        if module_index != -1
            let match_module = 1
        endif
    endfor

    if match_act == 1 && match_frontend == 1
        return 'action'
    endif
    if match_app == 1 && match_frontend == 1
        return 'action'
    endif
    if match_processor
        return 'processor'
    endif
    if match_aoi == 1
        return 'processor'
    endif
    if match_module == 1
        return 'module'
    endif
    return 'default'
endfunction

function! s:sort_method_numeric (i1, i2)
    return a:i1 - a:i2
endfunction

function! s:convert_input(input)
    let filename = expand("%:p")
    let pathes = split(filename, '/')
    let filetype = s:get_filetype(pathes)
    let tagtype = s:get_tagtype(a:input)

    if filetype ==# 'action'
        let input = s:convert_input_action(a:input, tagtype)
        return input
    endif

    if filetype ==# 'processor'
        let input = s:convert_input_processor(a:input, tagtype)
        return input
    endif

    if filetype ==# 'module'
        let input = s:convert_input_module(a:input, tagtype)
        return input
    endif

    return a:input
endfunction

function! s:convert_input_action(input, tag_type)
    let line  = getline('.')
    let match_aoi = match(line, '->' . 'aoi' . '->')

    if  a:tag_type ==# 'method' && match_aoi != -1

        let ic = &ignorecase
        set noignorecase

        let index = -1
        let index_list = []
        "remove snake case
        let input = substitute(a:input, '_', '', 'g')
        while 1
            let index = match(input, "[A-Z]", index + 1)
            if index == -1
                break
            endif
            let index_list = insert(index_list, index)
        endwhile

        let index_list = insert(index_list, 0)
        let index_list = insert(index_list, strlen(input))
        let index_list = sort(index_list, "s:sort_method_numeric")
        let path_list = []

        let i = 0
        while i < len(index_list) - 1
            let path = strpart(input, index_list[i], index_list[i+1] - index_list[i])
            let path = s:to_camel(path)
            let path_list = insert(path_list, path, len(path_list))
            let i = i+1
        endwhile

        let path_list = insert(path_list, 'Processor', 0)
        let input = join(path_list, '_')

        if ic == 1
            set ignorecase
        endif

        return input
    endif

    return a:input
endfunction

function! s:convert_input_processor(input, tag_type)
    let input = a:input
    let line = getline('.')
    let is_legacy = match(line, 'legacy_module')

    if a:tag_type ==# 'class'
        let pathes = split(a:input, '_')
        let path_list = []
        if is_legacy == -1
            let path_list = insert(path_list, 'Module', 0)
        else
            let path_list = insert(path_list, 'LegacyModule', 0)
        endif
        for path in pathes
            let path_list = insert(path_list, s:to_camel(path), len(path_list))
        endfor
        let input = join(path_list, '_')
    endif
    return input
endfunction

function! s:convert_input_module(input, tag_type)
    let input     = a:input
    let line      = getline('.')
    let is_data   = match(line, '->data->')
    let is_legacy = match(line, '->legacy_module->')
    let is_module = match(line, '->module->')
    let pathes    = split(line, '->')

    if len(pathes) >= 4
        let class_part      = pathes[2]
        let class_path_list = split(class_part, '_')
        let class_path_camelized = []
        for class_path in class_path_list
            let class_path_camelized = insert(class_path_camelized, s:to_camel(class_path), len(class_path_camelized))
        endfor
        let class_name = join(class_path_camelized, '_')
        if is_data != -1
            let class_name = class_name
        elseif is_legacy != -1
            let class_name = 'LegacyModule_' . class_name
        elseif is_module != -1
            let class_name = 'Module_' . class_name
        endif
    endif

    if a:tag_type ==# 'method' && is_data != -1
        let input = class_name
    endif

    if a:tag_type ==# 'class'
        let input = class_name
    endif

    return input
endfunction

function! s:to_camel(str)
    let camelized = substitute(a:str, '\v<(.)(\w*)', '\u\1\L\2', 'g')
    return camelized
endfunction

function! s:truncate(str, max, footer_width, sep, is_fill)
    if a:max==0
        return ''
    endif
    if g:unite_source_tag_strict_truncate_string
        return unite#util#truncate_smart(a:str, a:max, a:footer_width, a:sep)
    else
        let l = len(a:str)
        if l <= a:max
            if a:is_fill == 0
                return a:str
            else
                return a:str . repeat(' ', a:max - l)
            endif
        else
            if a:max != 0
                return a:str[0 : (l - a:footer_width-len(a:sep))]
                            \ .a:sep.a:str[-a:footer_width : -1]
        endif
    endif
endfunction

function! s:next(tagdata, line, name)
    let is_file = a:name ==# 'tag/file'
    let cont = a:tagdata.cont
    " parsing tag files is faster than using taglist()
    let [name, filename, cmd] = s:parse_tag_line(
    \    cont.encoding != '' ? iconv(a:line, cont.encoding, &encoding)
    \                        : a:line)

    " check comment line
    if empty(name)
        if filename != ''
            let cont.encoding = filename
        endif
        return []
    endif

    " when cmd shows line number
    let linenr = 0
    if cmd =~ '^\d\+$'
        let linenr = cmd - 0
    else
        " remove / or ? at the head and the end
        if cmd =~ '^[/?]'
            let pattern = cmd[1:-2]
        else
            let pattern = cmd
        endif
        " unescape /
        let pattern = substitute(pattern, '\\\/', '/', 'g')
        " use 'nomagic'
        let pattern = '\M' . pattern
    endif

    let path = filename =~ '^\%(/\|\a\+:[/\\]\)' ?
                \ filename :
                \ unite#util#substitute_path_separator(
                \   fnamemodify(cont.basedir . '/' . filename, ':p:.'))

    let abbr = s:truncate(name, g:unite_source_tag_max_name_length, 15, '..', 1)
    if g:unite_source_tag_show_fname
        let abbr .= '  '.
                    \ s:truncate('@'.fnamemodify(path,
                    \   (a:name ==# 'tag/include' ? ':t' : ':.')),
                    \   g:unite_source_tag_max_fname_length, 10, '..', 1)
    endif
    if g:unite_source_tag_show_location
        if linenr
            let abbr .= '  line:' . linenr
        else
            let abbr .= '  ' . matchstr(cmd, '^[?/]\^\?\zs.\{-1,}\ze\$\?[?/]$')
        endif
    endif

    let tag = {
    \   'word':    name,
    \   'abbr':    abbr,
    \   'kind':    'jump_list',
    \   'action__path':    path,
    \   'action__tagname': name
    \}
    if linenr
        let tag.action__line = linenr
    else
        let tag.action__pattern = pattern
    endif
    call add(a:tagdata.tags, tag)

    let result = is_file ? [] : [tag]

    let fullpath = fnamemodify(path, ':p')
    if !has_key(a:tagdata.files, fullpath)
        let file = {
        \   "word": fullpath,
        \   "abbr": fnamemodify(fullpath, ":."),
        \   "kind": "jump_list",
        \   "action__path": fullpath,
        \   "action__directory": unite#util#path2directory(fullpath),
        \ }
        let a:tagdata.files[fullpath] = file
        if is_file
            let result = [file]
        endif
    endif

    return result
endfunction

" Tag file format
"   tag_name<TAB>file_name<TAB>ex_cmd
"   tag_name<TAB>file_name<TAB>ex_cmd;"<TAB>extension_fields
" Parse
" 0. a line starting with ! is comment line
" 1. split extension_fields and others by separating the string at the last ;"
" 2. parse the former half by spliting it by <TAB>
" 3. the first part is tag_name, the second part is file_name
"    and ex_cmd is taken by joining remain parts with <TAB>
" 4. parsing extension_fields
function! s:parse_tag_line(line)
    " 0.
    if a:line[0] == '!'
        let enc = matchstr(a:line, '\C^!_TAG_FILE_ENCODING\t\zs\S\+\ze\t')
        return ['', enc, '']
    endif

    " 1.
    let tokens = split(a:line, ';"')
    let tokens_len = len(tokens)
    if tokens_len > 2
        let former = join(tokens[0:-2], ';"')
    elseif tokens_len == 2
        let former = tokens[0]
    else
        let former = a:line
    endif

    " 2.
    let fields = split(former, "\t")
    if len(fields) < 3
        return ['', '', '']
    endif

    " 3.
    let name = fields[0]
    let file = fields[1]
    let cmd = len(fields) == 3 ? fields[2] : join(fields[2:-1], "\t")

    " 4. TODO

    return [name, file, cmd]
endfunction
" " test case
" let s:test = 'Hoge	test.php	/^function Hoge()\/*$\/;"	f	test:*\/ {$/;"	f'
" echomsg string(s:parse_tag_line(s:test))
" let s:test = 'Hoge	Hoge/Fuga.php	/^class Hoge$/;"	c	line:15'
" echomsg string(s:parse_tag_line(s:test))


" action
let s:action_table = {}

let s:action_table.jump = {
\   'description': 'jump to the selected tag'
\}
function! s:action_table.jump.func(candidate)
    execute "tjump" a:candidate.action__tagname
endfunction

let s:action_table.select = {
\   'description': 'list the tags matching the selected tag pattern'
\}
function! s:action_table.select.func(candidate)
    execute "tselect" a:candidate.action__tagname
endfunction

let s:action_table.jsplit = {
\   'description': 'split window and jump to the selected tag',
\   'is_selectable': 1
\}
function! s:action_table.jsplit.func(candidates)
    for c in a:candidates
        execute "stjump" c.action__tagname
    endfor
endfunction

let s:source.action_table = s:action_table
let s:source_include.action_table = s:action_table

" vim:foldmethod=marker:fen:sw=4:sts=4
