# Fonia

Mixer nativo para macOS 14.4 ou superior. Na barra de menus, abra o ícone de controles e ajuste a saída padrão ou o volume de um aplicativo. O volume geral depende de suporte do dispositivo; algumas saídas HDMI e USB têm volume fixo.

## Executar

Com o toolchain da Apple e SDK do macOS 14.4 ou posterior:

```sh
make check
open build/Fonia.app
```

O build é local, para a arquitetura do Mac em uso, com assinatura ad hoc. Na primeira alteração de volume de um app, autorize o acesso ao áudio do sistema, se solicitado. O mixer não precisa do microfone. O modificador de voz pede essa permissão separadamente na primeira ativação.

## Modificador de voz

A engrenagem no rodapé do mixer abre **Ajustes**. Em **Geral**, ative **Iniciar com o Mac** para abrir o Fonia ao iniciar a sessão. A captura do microfone continua manual.

1. Escolha seu microfone físico em **Ajustes do Sistema → Som → Entrada**.
2. Na barra de menus, abra **Fonia → Modificador de voz**. Escolha Natural, Grave, Aguda ou Rádio.
3. Para se ouvir, selecione os fones em **Enviar para**. Para chamadas, abra **Ajustes → Microfone para chamadas → Instalar interface para chamadas…**. O Fonia baixa o pacote oficial do BlackHole 2ch, verifica o SHA-256 e abre o Instalador do macOS. Conclua a instalação; se o dispositivo não aparecer, reinicie o Mac. O Fonia sugere o BlackHole assim que o detecta. Escolha **BlackHole 2ch** também como **microfone** no Discord, Zoom ou OBS; mantenha a saída da chamada nos fones.
4. Clique em **Ativar microfone**. Troque o preset enquanto fala. Fechar o menu mantém a voz ativa; **Desativar microfone** encerra a captura.

O efeito roda localmente, sem gravar. A interface virtual é o BlackHole, instalado separadamente pelo Instalador do macOS. O Fonia não altera os dispositivos padrão. `make check` renderiza tons de teste offline e inicia o grafo de reprodução nas saídas disponíveis (padrão e uma alternativa), sem capturar o microfone. Para validar a rota completa, use o teste de microfone do app de chamada, alterne entre Natural e Grave e confirme que o sinal cessa ao desativar o microfone.

## Funcionamento

### Painel de sons

No menu do Fonia, abra **Painel de sons → Importar sons…** e selecione arquivos de áudio locais mono ou estéreo. Cada clipe ganha um botão e fica copiado na biblioteca do Fonia. No Discord, OBS ou outro aplicativo, escolha **BlackHole 2ch** como microfone. Um clique toca o clipe uma vez até o fim; clicar de novo reinicia do começo e clicar em outro som substitui o anterior. A voz pode continuar ativa em paralelo no mesmo destino. Fechar o painel interrompe o clipe. O menu de contexto de cada botão remove a cópia da biblioteca, preservando o original.

Com BlackHole 2ch ativo no sistema, **Ajustes → Microfone para chamadas → Remover BlackHole 2ch…** abre o desinstalador oficial após confirmação. Isso remove a interface de todos os aplicativos e pode interromper áudio em andamento. Instalação e remoção verificam SHA-256, assinatura do editor e notarização/Gatekeeper antes de abrir o pacote. Consulte [distribuição e revisão de versões](release/README.md).

`Fonia.swift` enumera as fontes em reprodução e apresenta controles SwiftUI. `Audio.m` usa taps privados do Core Audio: ao reduzir um aplicativo, silencia seu caminho original enquanto reproduz suas amostras estéreo com o ganho escolhido na saída padrão. Não salva amostras. Voltar para 100% libera o tap. Os níveis individuais duram a sessão; o ajuste geral altera a saída do sistema.

## Verificação

`make check` compila o app, verifica o bundle e testa a atenuação e o silêncio com amostras conhecidas, usando o mesmo callback do app. Para validar áudio no hardware:

1. Reproduza sons diferentes em dois apps. Abra o mixer e confirme as duas fontes.
2. Reduza uma a zero. A outra deve continuar tocando. Volte a 50% e depois a 100%.
3. Ajuste o controle geral em uma saída compatível. Confira a mudança no controle de volume do macOS.
4. Com um app atenuado, troque a saída padrão e confira a reprodução na nova saída. Encerre o Fonia e confirme que o volume individual volta ao original.
