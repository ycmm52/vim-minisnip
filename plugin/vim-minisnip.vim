" set default global variable values if unspecified by user
let g:minisnip_dir           = fnamemodify(get(g:, 'minisnip_dir', '~/.vim/minisnip'), ':p')
let g:minisnip_trigger       = get(g:, 'minisnip_trigger', '<Tab>')
let g:minisnip_startdelim    = get(g:, 'minisnip_startdelim', '{{+')
let g:minisnip_enddelim      = get(g:, 'minisnip_enddelim', '+}}')
let g:minisnip_evalmarker    = get(g:, 'minisnip_evalmarker', '~')
let g:minisnip_backrefmarker = get(g:, 'minisnip_backrefmarker', '\\~')
let g:minisnip_enable        = get(g:, 'minisnip_enable', 1)

" this is the pattern used to find placeholders
let s:delimpat = '\V' . g:minisnip_startdelim . '\.\{-}' . g:minisnip_enddelim

function! <SID>ShouldTrigger()
    silent! unlet! s:snippetfile
    if &ft == 'snip' || g:minisnip_enable != 1
        return 0
    endif
    let l:cword = matchstr(getline('.'), '\v\w+%' . col('.') . 'c')
    " let l:cword = expand('<cword>')
    let s:cword = l:cword

    " look for a snippet by filetype and name
    let l:filename = l:cword . '.' . 'snip'
    let l:snippetfile = g:minisnip_dir . '/' . l:filename
    let l:ft_snippetfile = g:minisnip_dir . '/' . &filetype . '/' . l:filename
    if filereadable(l:ft_snippetfile)
        " filetype snippets override general snippets
        let l:snippetfile = l:ft_snippetfile
    endif

    " make sure the snippet exists
    if filereadable(l:snippetfile)
        let s:snippetfile = expand(l:snippetfile)
        return 1
    endif

    return search(s:delimpat, 'e')
endfunction

" main function, called on press of Tab (or whatever key Minisnip is bound to)
function! <SID>Minisnip()
    if exists("s:snippetfile")
        " reset placeholder text history (for backrefs)
        let s:placeholder_texts = []
        let s:placeholder_text = ''
        let s:snippetContent = readfile(expand( s:snippetfile ))
        call s:echodebug('cword', s:cword)
        if len(s:snippetContent) == 1
            let currentLine = s:GetCurrentLine()
            let currentCol = s:GetCurrentCol()
            let line = getline('.')
            let leadingSpaceNum = indent(currentLine)
            let newLine = substitute(line, '\<' . s:cword . '\>', s:snippetContent[0], '')
            call setline(currentLine, newLine)
        " set indentation if snippet line > 1
        elseif len(s:snippetContent) > 1
            let s:currentLineNr = line('.')
            let s:indentation = indent('.')
            for i in range(0, len(s:snippetContent)-1)
                let finalLine = repeat(' ', s:indentation) . s:snippetContent[i]
                if i == 0
                    let line = getline('.')
                    let finalLine = substitute(line, '\<' . s:cword . '\>', s:snippetContent[i], '')
                    call setline(s:currentLineNr, finalLine)
                else
                    call append(s:currentLineNr+i-1, finalLine)
                endif
            endfor
        endif
        " select the first placeholder
        call s:SelectPlaceholder()
    else
        " save the current placeholder's text so we can backref it
        let l:old_s = @s
        normal! ms"syv`<`s
        let s:placeholder_text = @s
        let @s = l:old_s
        " jump to the next placeholder
        call s:SelectPlaceholder()
    endif
endfunction

" this is the function that finds and selects the next placeholder
function! s:SelectPlaceholder()
    " don't clobber s register
    let l:old_s    = @s
    let l:old_plus = @p
    let l:old_star = @t

    " get the contents of the placeholder
    " we use /e here in case the cursor is already on it (which occurs ex.
    "   when a snippet begins with a placeholder)
    " we also use keeppatterns to avoid clobbering the search history /
    "   highlighting all the other placeholders
    keeppatterns execute 'normal! /' . s:delimpat . "/e\<cr>gn\"sy"

    " save the contents of the previous placeholder (for backrefs)
    call add(s:placeholder_texts, s:placeholder_text)

    " save length of entire placeholder for reference later
    let l:slen = len(@s)

    " remove the start and end delimiters
    let @s=substitute(@s, '\V' . g:minisnip_startdelim, '', '')
    let @s=substitute(@s, '\V' . g:minisnip_enddelim, '', '')

    " is this placeholder marked as 'evaluate'?
    if @s =~ '\V\^' . g:minisnip_evalmarker
        " remove the marker
        let @s=substitute(@s, '\V\^' . g:minisnip_evalmarker, '', '')
        " substitute in any backrefs
        let @s=substitute(@s, '\V' . g:minisnip_backrefmarker . '\(\d\)',
            \"\\=\"'\" . substitute(get(
            \    s:placeholder_texts,
            \    len(s:placeholder_texts) - str2nr(submatch(1)), ''
            \), \"'\", \"''\", 'g') . \"'\"", 'g')
        " evaluate what's left
        let @s=eval(@s)
    endif

    if empty(@s)
        " the placeholder was empty, so just enter insert mode directly
        normal! gvd
        call feedkeys(col("'>") - l:slen >= col('$') - 1 ? 'a' : 'i', 'n')
    else
        " paste the placeholder's default value in and enter select mode on it
        execute "normal! gv\"spgv\<C-g>"
    endif

    " restore old value of s register
    let @s = l:old_s
    let @p = l:old_plus
    let @t = l:old_star
endfunction

function! s:GetCurrentLine() abort
    return getcurpos()[1]
endfunction

function! s:GetCurrentCol() abort
    return getcurpos()[2]
endfunction

function! s:echodebug(msg, ...) abort
    let file=expand('%')
    let time=strftime("%T")
    let date=strftime("%Y%m%d")
    let msg= " [DEBUG] [" . time . " " . date . "] [" . file . "] DebugMsg: ". a:msg . " = " . s:JoinListElement(a:000)
    redir >> ~/vimdebug
    execute ":echo msg"
    redir END
endfunction

function! s:JoinListElement(list) abort
    let nl = map(deepcopy(a:list), 'string(v:val)')
    return join(nl, ", ")
endfunction

" plug mappings
" the eval/escape charade is to convert ex. <Tab> into a literal tab, first
" making it \<Tab> and then eval'ing that surrounded by double quotes
if g:minisnip_enable == 1
    inoremap <script> <expr> <Plug>Minisnip <SID>ShouldTrigger() ?
                \"x\<bs>\<esc>:call \<SID>Minisnip()\<cr>" :
                \eval('"' . escape(g:minisnip_trigger, '\"<') . '"')
    snoremap <script> <expr> <Plug>Minisnip <SID>ShouldTrigger() ?
                \"\<esc>:call \<SID>Minisnip()\<cr>" :
                \eval('"' . escape(g:minisnip_trigger, '\"<') . '"')

    " add the default mappings if the user hasn't defined any
    if !hasmapto('<Plug>Minisnip')
        execute 'imap <unique> ' . g:minisnip_trigger . ' <Plug>Minisnip'
        execute 'smap <unique> ' . g:minisnip_trigger . ' <Plug>Minisnip'
    endif
endif
