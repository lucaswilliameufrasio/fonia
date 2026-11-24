# Distribuição do Fonia

## Fluxo no GitHub

Execute **Actions → Prepare Release** na `main` com a versão desejada. Revise o PR com versão do bundle e changelog. Após o merge, atualize a `main`, marque o commit com `git tag vX.Y.Z` e envie a tag com `git push origin vX.Y.Z`. O workflow de tag compila e testa o app no macOS sem depender de dispositivos físicos. A primeira tag do projeto acompanha o commit inicial.

Tags com `-alpha.N`, `-beta.N` ou `-rc.N` publicam automaticamente o ZIP do app ad hoc, seu SHA-256 e notas com as mudanças do changelog, arquitetura, requisito de macOS e instruções de instalação. Tags estáveis criam **rascunhos** com as notas do changelog: no Mac de distribuição, confira a tag, produza e valide o ZIP conforme abaixo, anexe-o à release com o SHA-256 e só então publique. Não distribua builds ad hoc como builds notarizados.

O `.app` de `make` é um build local ad hoc. Para gerar uma cópia para distribuição, configure no Chaveiro do Mac uma identidade Apple **Developer ID Application** com chave privada e um perfil do `xcrun notarytool store-credentials`. Mantenha os segredos no Chaveiro. Na raiz do projeto, execute `make release` com `SIGN_IDENTITY` (nome completo da identidade) e `NOTARY_PROFILE` (nome do perfil) no ambiente. Essa ação envia uma cópia assinada do Fonia à Apple. Não publica o app nem inclui o BlackHole.

O processo usa a arquitetura do Mac de build, exige `make check`, assina com hardened runtime e timestamp, aguarda aprovação da Apple, anexa o ticket e verifica stapler e Gatekeeper. Só depois produz `build/release.*/Fonia-macOS.zip` e imprime o SHA-256. Antes de publicar, teste esse ZIP em outro Mac compatível, incluindo a permissão do microfone e o áudio em uma chamada.

## Revisão obrigatória dos pacotes externos

Não seguir `latest`, atualizar o hash automaticamente após uma falha nem embutir o driver. Cada ação em `VirtualMicSetup.swift` tem seu próprio arquivo e SHA-256. O pacote de instalação revisado é o **0.7.1**, publicado pela [Existential Audio](https://github.com/ExistentialAudio/BlackHole); o desinstalador 2ch oficial tem URL sem versão, por isso seu conteúdo também está fixado. O editor esperado para ambos é **Existential Audio Inc. (Q5C99V536K)**.

Para aceitar uma atualização:

1. Consulte as notas de release, avisos de segurança e o link no projeto oficial. Obtenha o `.pkg` pelo domínio `existential.audio`. Compare a versão e o hash do instalador com o [cask Homebrew](https://formulae.brew.sh/cask/blackhole-2ch). Não trate o hash servido junto com o arquivo como prova de autoria.
2. Sem instalar, use `shasum -a 256 arquivo.pkg`, `pkgutil --check-signature arquivo.pkg` e `spctl --assess --type install -vv arquivo.pkg`. Exija o editor previsto e `Notarized Developer ID`. Mudança de Team ID precisa de confirmação independente do fornecedor.
3. Use `pkgutil --expand arquivo.pkg pasta-nova` e examine scripts, destinos da instalação e efeitos no serviço de áudio. O desinstalador atual remove `/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver` e reinicia o Core Audio. Reveja impacto e aviso no app se isso mudar.
4. Registre URL, versão ou data, hash, editor, mudanças relevantes e resultado dos testes na revisão de código. Atualize o pin da ação revisada e rode `make check` e `build/route-checks --check-package`. O último comando verifica ambos os pacotes reais, sem abri-los.
5. Em um Mac de teste, valide instalação, áudio em uma chamada e remoção com o Instalador do macOS. Só então distribua um novo Fonia assinado. Se houver suspeita sobre uma versão já aprovada, suspenda a distribuição e publique um build com o pacote desabilitado ou substituído. Os pins de builds antigos não mudam remotamente.
