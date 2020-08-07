if exists('g:loaded_abolish')
    finish
endif
let g:loaded_abolish = 1

" Source:
" https://github.com/tpope/vim-abolish/blob/master/plugin/abolish.vim

import Catch from 'lg.vim'

" Utility functions {{{1

fu s:function(name) abort
    return substitute(a:name, '^s:', expand('<sfile>')->matchstr('.*\zs<SNR>\d\+_'), '')
        \ ->function()
endfu

fu s:send(self, func, ...) abort
    if type(a:func) == v:t_string || type(a:func) == v:t_number
        let l:Func = get(a:self, a:func, '')
    else
        let l:Func = a:func
    endif
    let s = type(a:self) == v:t_dict ? a:self : {}
    if type(l:Func) == v:t_func
        return call(l:Func, a:000, s)
    elseif type(l:Func) == v:t_dict && has_key(l:Func, 'apply')
        return call(l:Func.apply, a:000, l:Func)
    elseif type(l:Func) == v:t_dict && has_key(l:Func, 'call')
        return call(l:Func.call, a:000, s)
    elseif type(l:Func) == v:t_string && l:Func == '' && has_key(s, 'function missing')
        return call('s:send', [s, 'function missing', a:func] + a:000)
    else
        return l:Func
    endif
endfu

let s:object = {}
fu s:object.clone(...) abort
    let sub = deepcopy(self)
    return a:0 ? extend(sub, a:1) : sub
endfu

if !exists('g:Abolish')
    let Abolish = {}
endif
call extend(Abolish, s:object, 'force')
call extend(Abolish, {'Coercions': {}}, 'keep')

fu s:throw(msg) abort
    let v:errmsg = a:msg
    throw 'Abolish: ' .. a:msg
endfu

fu s:words() abort
    let words = []
    let lnum = line('w0')
    while lnum <= line('w$')
        let line = getline(lnum)
        let col = 0
        while match(line, '\<\k\k\+\>', col) != -1
            let words += [matchstr(line, '\<\k\k\+\>', col)]
            let col = matchend(line, '\<\k\k\+\>', col)
        endwhile
        let lnum += 1
    endwhile
    return words
endfu

fu s:extractopts(list, opts) abort
    let i = 0
    while i < len(a:list)
        if a:list[i] =~ '^-[^=]' && has_key(a:opts, matchstr(a:list[i], '-\zs[^=]*'))
            let key = matchstr(a:list[i], '-\zs[^=]*')
            let value = matchstr(a:list[i], '=\zs.*')
            if get(a:opts, key)->type() == v:t_list
                let a:opts[key] += [value]
            elseif get(a:opts, key)->type() == v:t_number
                let a:opts[key] = 1
            else
                let a:opts[key] = value
            endif
        else
            let i += 1
            continue
        endif
        call remove(a:list, i)
    endwhile
    return a:opts
endfu
" }}}1
" Dictionary creation {{{1

fu s:mixedcase(word) abort
    return substitute(s:camelcase(a:word), '^.', '\u&', '')
endfu

fu s:camelcase(word) abort
    let word = substitute(a:word, '-', '_', 'g')
    if word !~# '_' && word =~# '\l'
        return substitute(word, '^.', '\l&', '')
    else
        let pat = '\=submatch(1) == "" ? submatch(2)->tolower() : submatch(2)->toupper()'
        return substitute(word, '\C\(_\)\=\(.\)', pat, 'g')
    endif
endfu

fu s:snakecase(word) abort
    let word = substitute(a:word, '::', '/', 'g')
    let word = substitute(word, '\(\u\+\)\(\u\l\)', '\1_\2', 'g')
    let word = substitute(word, '\(\l\|\d\)\(\u\)', '\1_\2', 'g')
    let word = substitute(word, '[.-]', '_', 'g')
    let word = tolower(word)
    return word
endfu

fu s:uppercase(word) abort
    return s:snakecase(a:word)->toupper()
endfu

fu s:dashcase(word) abort
    return s:snakecase(a:word)->substitute('_', '-', 'g')
endfu

fu s:spacecase(word) abort
    return s:snakecase(a:word)->substitute('_', ' ', 'g')
endfu

fu s:dotcase(word) abort
    return s:snakecase(a:word)->substitute('_', '.', 'g')
endfu

fu s:titlecase(word) abort
    return s:spacecase(a:word)->substitute('\(\<\w\)', '\=submatch(1)->toupper()', 'g')
endfu

call extend(Abolish, {
    \ 'camelcase': s:function('s:camelcase'),
    \ 'mixedcase': s:function('s:mixedcase'),
    \ 'snakecase': s:function('s:snakecase'),
    \ 'uppercase': s:function('s:uppercase'),
    \ 'dashcase': s:function('s:dashcase'),
    \ 'dotcase': s:function('s:dotcase'),
    \ 'spacecase': s:function('s:spacecase'),
    \ 'titlecase': s:function('s:titlecase')
    \ }, 'keep')

fu s:create_dictionary(lhs, rhs, opts) abort
    let dictionary = {}
    let i = 0
    let expanded = s:expand_braces({a:lhs : a:rhs})
    for [lhs, rhs] in items(expanded)
        if get(a:opts, 'case', 1)
            let dictionary[s:mixedcase(lhs)] = s:mixedcase(rhs)
            let dictionary[tolower(lhs)] = tolower(rhs)
            let dictionary[toupper(lhs)] = toupper(rhs)
        endif
        let dictionary[lhs] = rhs
    endfor
    let i += 1
    return dictionary
endfu

fu s:expand_braces(dict) abort
    let new_dict = {}
    for [key, val] in items(a:dict)
        if key =~ '{.*}'
            let redo = 1
            let [all, kbefore, kmiddle, kafter;crap] = matchlist(key, '\(.\{-\}\){\(.\{-\}\)}\(.*\)')
            let [all, vbefore, vmiddle, vafter;crap] = matchlist(val, '\(.\{-\}\){\(.\{-\}\)}\(.*\)') + ['', '', '', '']
            if all == ''
                let [vbefore, vmiddle, vafter] = [val, ',', '']
            endif
            let targets = split(kmiddle, ',', 1)
            let replacements = split(vmiddle, ',', 1)
            if replacements ==# ['']
                let replacements = targets
            endif
            for i in range(0, len(targets) - 1)
                let new_dict[kbefore .. targets[i] .. kafter] =
                    \ vbefore .. replacements[i % len(replacements)] .. vafter
            endfor
        else
            let new_dict[key] = val
        endif
    endfor
    if exists('redo')
        return s:expand_braces(new_dict)
    else
        return new_dict
    endif
endfu
" }}}1
" Abolish Dispatcher {{{1

fu s:SubComplete(A, L, P) abort
    if a:A =~ '^[/?]\k\+$'
        let char = strpart(a:A, 0, 1)
        return s:words()->map({_, v -> char .. v})->join("\n")
    elseif a:A =~# '^\k\+$'
        return join(s:words(), "\n")
    endif
endfu

fu s:Complete(A, L, P) abort
    " Vim bug: :Abolish -<Tab> calls this function with a:A equal to 0
    return a:A =~# '^[^/?-]' && type(a:A) != v:t_number
        \ ?     join(s:words(), "\n")
        \ : a:L =~# '^\w\+\s\+\%(-\w*\)\=$'
        \ ?     "-search\n-substitute\n-delete\n-buffer\n-cmdline\n"
        \ : a:L =~# ' -\%(search\|substitute\)\>'
        \ ?     '-flags='
        \ :     "-buffer\n-cmdline"
endfu

let s:commands = {}
let s:commands.abstract = s:object.clone()

fu s:commands.abstract.dispatch(bang, line1, line2, count, args) abort
    return self.clone().go(a:bang, a:line1, a:line2, a:count, a:args)
endfu

fu s:commands.abstract.go(bang, line1, line2, count, args) abort
    let self.bang = a:bang
    let self.line1 = a:line1
    let self.line2 = a:line2
    let self.count = a:count
    return self.process(a:bang, a:line1, a:line2, a:count, a:args)
endfu

fu s:dispatcher(bang, line1, line2, count, args) abort
    let i = 0
    let args = copy(a:args)
    let command = s:commands.abbrev
    while i < len(args)
        if args[i] =~# '^-\w\+$' && has_key(s:commands, matchstr(args[i], '-\zs.*'))
            let command = s:commands[matchstr(args[i], '-\zs.*')]
            call remove(args, i)
            break
        endif
        let i += 1
    endwhile
    try
        return command.dispatch(a:bang, a:line1, a:line2, a:count, args)
    catch /^Abolish: /
        return s:Catch()
    endtry
    return ''
endfu
" }}}1
" Subvert Dispatcher {{{1

fu s:subvert_dispatcher(bang, line1, line2, count, args) abort
    try
        return s:parse_subvert(a:bang, a:line1, a:line2, a:count, a:args)
    catch /^Subvert: /
        return s:Catch()
    endtry
endfu

fu s:parse_subvert(bang, line1, line2, count, args) abort
    if a:args =~ '^\%(\w\|$\)'
        let args = (a:bang ? '!' : '') .. a:args
    else
        let args = a:args
    endif
    let separator = matchstr(args, '^.')
    let split = split(args, separator, 1)[1:]

    return a:count || split ==# ['']
        \ ?     s:parse_substitute(a:bang, a:line1, a:line2, a:count, split)
        \
        \ : len(split) == 1
        \ ?     s:find_command(separator, '', split[0])
        \
        \ : len(split) == 2 && split[1] =~# '^[A-Za-z]*n[A-Za-z]*$'
        \ ?     s:parse_substitute(a:bang, a:line1, a:line2, a:count, [split[0], '', split[1]])
        \
        \ : len(split) == 2 && split[1] =~# '^[A-Za-z]*\%([+-]\d\+\)\=$'
        \ ?     s:find_command(separator, split[1], split[0])
        \
        \ : len(split) >= 2 && split[1] =~# '^[A-Za-z]* '
        \ ?     s:grep_command(rest, a:bang, flags, split[0])
        \
        \ : len(split) >= 2 && separator == ' '
        \ ?     s:grep_command(join(split[1:], ' '), a:bang, '', split[0])
        \
        \ :     s:parse_substitute(a:bang, a:line1, a:line2, a:count, split)
endfu

fu s:normalize_options(flags) abort
    if type(a:flags) == v:t_dict
        let opts = a:flags
        let flags = get(a:flags, 'flags', '')
    else
        let opts = {}
        let flags = a:flags
    endif
    if flags =~# 'w'
        let opts.boundaries = 2
    elseif flags =~# 'v'
        let opts.boundaries = 1
    elseif !has_key(opts, 'boundaries')
        let opts.boundaries = 0
    endif
    let opts.case = (flags !~# 'I' ? get(opts, 'case', 1) : 0)
    let opts.flags = substitute(flags, '\C[avIiw]', '', 'g')
    return opts
endfu
" }}}1
" Searching {{{1

fu s:subesc(pattern) abort
    return substitute(a:pattern, '[][\\/.*+?~%()&]', '\\&', 'g')
endfu

fu s:sort(a, b) abort
    if a:a ==? a:b
        return a:a == a:b ? 0 : a:a > a:b ? 1 : -1
    elseif strlen(a:a) == strlen(a:b)
        return a:a >? a:b ? 1 : -1
    else
        return strlen(a:a) < strlen(a:b) ? 1 : -1
    endif
endfu

fu s:pattern(dict, boundaries) abort
    if a:boundaries == 2
        let a = '<'
        let b = '>'
    elseif a:boundaries
        " TODO: Replace `@<=` with `@1<=`?
        let a = '%(<|_@<=|[[:lower:]]@<=[[:upper:]]@=)'
        let b = '%(>|_@=|[[:lower:]]@<=[[:upper:]]@=)'
    else
        let a = ''
        let b = ''
    endif
    return '\v\C' .. a .. '%(' .. keys(a:dict)
        \ ->sort(function('s:sort'))
        \ ->map({_, v -> s:subesc(v)})
        \ ->join('|')
        \ .. ')' .. b
endfu

fu s:egrep_pattern(dict, boundaries) abort
    let [a, b] = a:boundaries == 2
        \ ?     ['\<', '\>']
        \ : a:boundaries
        \ ?     ['(\<\|_)', '(\>\|_\|[[:upper:]][[:lower:]])']
        \ :     ['', '']

    return a .. '(' .. keys(a:dict)
        \ ->sort(function('s:sort'))
        \ ->map({_, v -> s:subesc(v)})
        \ ->join('\|')
        \ .. ')' .. b
endfu

fu s:c() abort
    call histdel('search', -1)
    return ''
endfu

fu s:find_command(cmd, flags, word) abort
    let opts = s:normalize_options(a:flags)
    let dict = s:create_dictionary(a:word, '', opts)
    " This is tricky.  If we use :/pattern, the search drops us at the
    " beginning of the line, and we can't use position flags (e.g., /foo/e).
    " If we use :norm /pattern, we leave ourselves vulnerable to "press enter"
    " prompts (even with :silent).
    let cmd = (a:cmd =~ '[?!]' ? '?' : '/')
    call setreg('/', [s:pattern(dict, opts.boundaries)], 'c')
    if opts.flags == '' || !search(@/, 'n')
        return 'norm! ' .. cmd .. "\<cr>"
    elseif opts.flags =~ ';[/?]\@!'
        call s:throw("E386: Expected '?' or '/' after ';'")
    else
        return "exe 'norm! " .. cmd .. cmd .. opts.flags .. "\<cr>'|call histdel('search', -1)"
    endif
endfu

fu s:grep_command(args, bang, flags, word) abort
    let opts = s:normalize_options(a:flags)
    let dict = s:create_dictionary(a:word, '', opts)
    if &grepprg == 'internal'
        let lhs = "'" .. s:pattern(dict, opts.boundaries) .. "'"
    else
        let lhs = "-E '" .. s:egrep_pattern(dict, opts.boundaries) .. "'"
    endif
    return 'grep' .. (a:bang ? '!' : '') .. ' ' .. lhs .. ' ' .. a:args
endfu

let s:commands.search = s:commands.abstract.clone()
let s:commands.search.options = {'word': 0, 'variable': 0, 'flags': ''}

fu s:commands.search.process(bang, line1, line2, count, args) abort
    call s:extractopts(a:args, self.options)
    if self.options.word
        let self.options.flags ..= 'w'
    elseif self.options.variable
        let self.options.flags ..= 'v'
    endif
    let opts = s:normalize_options(self.options)
    if len(a:args) > 1
        return s:grep_command(join(a:args[1:], ' '), a:bang, opts, a:args[0])
    elseif len(a:args) == 1
        return s:find_command(a:bang ? '!' : ' ', opts, a:args[0])
    else
        call s:throw('E471: Argument required')
    endif
endfu
" }}}1
" Substitution {{{1

fu Abolished() abort
    return get(g:abolish_last_dict, submatch(0), submatch(0))
endfu

fu s:substitute_command(cmd, bad, good, flags) abort
    let opts = s:normalize_options(a:flags)
    let dict = s:create_dictionary(a:bad, a:good, opts)
    let lhs = s:pattern(dict, opts.boundaries)
    let g:abolish_last_dict = dict
    return a:cmd .. '/' .. lhs .. '/\=Abolished()' .. '/' .. opts.flags
endfu

fu s:parse_substitute(bang, line1, line2, count, args) abort
    if get(a:args, 0, '') =~ '^[/?'']'
        let separator = matchstr(a:args[0], '^.')
        let args = join(a:args, ' ')->split(separator, 1)
        call remove(args, 0)
    else
        let args = a:args
    endif
    if len(args) < 2
        call s:throw('E471: Argument required')
    elseif len(args) > 3
        call s:throw('E488: Trailing characters')
    endif
    let [bad, good, flags] = (args + [''])[0:2]
    if a:count == 0
        let cmd = 'substitute'
    else
        let cmd = a:line1 .. ',' .. a:line2 .. 'substitute'
    endif
    return s:substitute_command(cmd, bad, good, flags)
endfu

let s:commands.substitute = s:commands.abstract.clone()
let s:commands.substitute.options = {'word': 0, 'variable': 0, 'flags': 'g'}

fu s:commands.substitute.process(bang, line1, line2, count, args) abort
    call s:extractopts(a:args, self.options)
    if self.options.word
        let self.options.flags ..= 'w'
    elseif self.options.variable
        let self.options.flags ..= 'v'
    endif
    let opts = s:normalize_options(self.options)
    if len(a:args) <= 1
        call s:throw('E471: Argument required')
    else
        let good = join(a:args[1:], '')
        let cmd = a:bang ? '.' : '%'
        return s:substitute_command(cmd, a:args[0], good, self.options)
    endif
endfu
" }}}1
" Abbreviations {{{1

fu s:badgood(args) abort
    let words = copy(a:args)->filter({_, v -> v !~ '^-'})
    call filter(a:args, {_, v -> v =~ '^-'})
    if empty(words)
        call s:throw('E471: Argument required')
    elseif !empty(a:args)
        call s:throw('Unknown argument: ' .. a:args[0])
    endif
    let [bad; words] = words
    return [bad, join(words, ' ')]
endfu

fu s:abbreviate_from_dict(cmd, dict) abort
    for [lhs, rhs] in items(a:dict)
        exe a:cmd .. ' ' .. lhs .. ' ' .. rhs
    endfor
endfu

let s:commands.abbrev = s:commands.abstract.clone()
let s:commands.abbrev.options = {'buffer':0, 'cmdline':0, 'delete':0}
fu s:commands.abbrev.process(bang, line1, line2, count, args) abort
    let args = copy(a:args)
    call s:extractopts(a:args, self.options)
    if self.options.delete
        let cmd = 'unabbrev'
        let good = ''
    else
        let cmd = 'noreabbrev'
    endif
    if !self.options.cmdline
        let cmd = 'i' .. cmd
    endif
    if self.options.delete
        let cmd = ' sil! ' .. cmd
    endif
    if self.options.buffer
        let cmd = cmd .. ' <buffer>'
    endif
    let [bad, good] = s:badgood(a:args)
    if substitute(bad, '[{},]', '', 'g') !~# '^\k*$'
        call s:throw('E474: Invalid argument (not a keyword: ' .. string(bad) .. ')')
    endif
    if !self.options.delete && good == ''
        call s:throw('E471: Argument required' .. a:args[0])
    endif
    let dict = s:create_dictionary(bad, good, self.options)
    call s:abbreviate_from_dict(cmd, dict)
    return ''
endfu

let s:commands.delete = s:commands.abbrev.clone()
let s:commands.delete.options.delete = 1
" }}}1

" Interface {{{1
" Mapping {{{2

fu s:unknown_coercion(letter, word) abort
    return a:word
endfu

call extend(Abolish.Coercions, {
    \ 'c': Abolish.camelcase,
    \ 'm': Abolish.mixedcase,
    \ 's': Abolish.snakecase,
    \ 'u': Abolish.uppercase,
    \ 'k': Abolish.dashcase,
    \ '.': Abolish.dotcase,
    \ ' ': Abolish.spacecase,
    \ 't': Abolish.titlecase,
    \ 'function missing': s:function('s:unknown_coercion')
    \ }, 'keep')

fu s:get_transformation() abort
    let s:transformation = getchar()->nr2char()
endfu

fu s:coerce(...) abort
    if !a:0
        call s:get_transformation()
        let &opfunc = expand('<sfile>')->matchstr('<SNR>\w*$')
        return 'g@l'
    endif
    let cb_save = &cb
    try
        set cb=
        let reg_save = getreginfo('"')
        let c = v:count1
        while c > 0
            let c -= 1
            norm! yiw
            let word = @@
            let @@ = s:send(g:Abolish.Coercions, s:transformation, word)
            if !exists('begin')
                let begin = getpos("'[")
            endif
            if word isnot# @@
                norm! viwpw
            else
                norm! w
            endif
        endwhile
        call setreg('"', reg_save)
        call setpos("'[", begin)
        " Why `+ [begin[2]]`?{{{
        "
        " So that the cursor doesn't jump  to an unexpected column position when
        " we move vertically *right after* a coercion.
        " Basically,  we  extend  the  position  described  by  `begin`  with  a
        " `curswant` number describing the current column position.
        "}}}
        call setpos('.', begin + [begin[2]])
        let &cb = cb_save
    endtry
endfu

nno <expr> cr <sid>coerce()

" TODO: add a visual mode mapping to be able to change `foo bar baz` into `foo_bar_baz`.
" https://github.com/tpope/vim-abolish/issues/74

" Commands {{{2

com -nargs=+ -bang -bar -range=0 -complete=custom,s:Complete Abolish
    \ exe s:dispatcher(<bang>0, <line1>, <line2>, <count>, [<f-args>])

com -nargs=1 -bang -bar -range=0 -complete=custom,s:SubComplete S
    \ exe s:subvert_dispatcher(<bang>0, <line1>, <line2>, <count>, <q-args>)

com -nargs=1 -bang -bar -range=0 -complete=custom,s:SubComplete Subvert
    \ exe s:subvert_dispatcher(<bang>0, <line1>, <line2>, <count>, <q-args>)

