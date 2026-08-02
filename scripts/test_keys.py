#!/usr/bin/env python3
"""Confere se o teclado produz os caracteres que o keymap ABNT2 promete.

Dois modos:

    ./scripts/test_keys.py           roteiro guiado: pede um caractere por vez
    ./scripts/test_keys.py --livre   eco: mostra o que chega, tecla a tecla

O roteiro compara o que chegou com o esperado e, no fim, lista o que falhou
junto da posicao onde a tecla deveria estar. O modo livre serve para caçar uma
tecla especifica sem seguir a ordem.

Acentos mortos (agudo, crase, til, circunflexo) so viram caractere depois da
vogal -- e o que o roteiro pede. Para testar o acento sozinho, aperte-o e
depois a barra de espaco: sai o acento solto.
"""

import sys
import termios
import tty
import unicodedata


class Target:
    """Um caractere a conferir e a posicao onde ele mora no keymap."""

    def __init__(self, char, where, note=""):
        self.char = char
        self.where = where
        self.note = note


class Palette:
    GREEN = "\033[0;32m"
    RED = "\033[0;31m"
    YELLOW = "\033[1;33m"
    DIM = "\033[2m"
    OFF = "\033[0m"


class Roteiro:
    """O conjunto de caracteres que o keymap ABNT2 deve produzir."""

    ITEMS = [
        # Acentos -- o motivo de todo o trabalho.
        Target("é", "BASE: tecla 'Num' (canto sup. dir.), depois E"),
        Target("á", "BASE: tecla 'Num', depois A"),
        Target("ó", "BASE: tecla 'Num', depois O"),
        Target("ã", "BASE: tecla \"'\\\"\" (fim da fileira do meio), depois A"),
        Target("õ", "BASE: tecla \"'\\\"\", depois O"),
        Target("ê", "BASE: Shift + tecla \"'\\\"\", depois E"),
        Target("â", "BASE: Shift + tecla \"'\\\"\", depois A"),
        Target("à", "LOWER + tecla \"'\\\"\" (crase), depois A"),
        Target("ç", "BASE: tecla ';:' (fim da fileira do meio)"),

        # Os que estavam inalcancaveis antes.
        Target("/", "LOWER + tecla 'H'"),
        Target("?", "LOWER + tecla 'J'"),
        Target("\\", "LOWER + tecla 'P'"),
        Target("|", "LOWER + tecla 'N'"),

        # Pontuacao da base.
        Target(";", "BASE: tecla '/?' (fileira de baixo, penultima)"),
        Target(":", "LOWER + tecla 'L'"),
        Target(",", "BASE: tecla ',<'"),
        Target(".", "BASE: tecla '.>'"),
        Target("'", "BASE: tecla '`~' (canto sup. esq.)"),
        Target('"', "BASE: Shift + tecla '`~'"),

        # Colchetes e chaves.
        Target("[", "LOWER + tecla 'Y'"),
        Target("]", "LOWER + tecla 'U'"),
        Target("{", "LOWER + tecla 'I'"),
        Target("}", "LOWER + tecla 'O'"),

        # Matematica -- fileira de baixo do lower, metade esquerda.
        Target("=", "LOWER + tecla 'Z'"),
        Target("-", "LOWER + tecla 'X'"),
        Target("+", "LOWER + tecla 'C'"),
        Target("_", "LOWER + tecla 'V'"),
        Target("*", "LOWER + tecla 'B'"),

        # Shift na fileira de numeros, igual a um 105 teclas.
        Target("!", "BASE: Shift + 1"),
        Target("@", "BASE: Shift + 2"),
        Target("#", "BASE: Shift + 3"),
        Target("$", "BASE: Shift + 4"),
        Target("%", "BASE: Shift + 5"),
        Target("&", "BASE: Shift + 7"),
        Target("(", "BASE: Shift + 9"),
        Target(")", "BASE: Shift + 0"),
    ]


class Reader:
    """Le um caractere sem esperar Enter, preservando o terminal."""

    @staticmethod
    def one_char():
        fd = sys.stdin.fileno()
        saved = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            data = sys.stdin.read(1)
            # Caracteres acentuados chegam em varios bytes; o read(1) do modo
            # texto ja devolve o caractere inteiro, mas sequencias de escape
            # (setas, F-keys) vem em pedaços -- drena-las evita lixo na proxima
            # leitura.
            if data == "\x1b":
                import select

                while select.select([sys.stdin], [], [], 0.05)[0]:
                    sys.stdin.read(1)
                return "\x1b"
            return data
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, saved)

    @staticmethod
    def describe(char):
        if char in ("\r", "\n"):
            return "Enter"
        if char == " ":
            return "espaco"
        if char == "\x1b":
            return "Esc"
        if ord(char) < 32:
            return f"controle 0x{ord(char):02x}"
        try:
            name = unicodedata.name(char)
        except ValueError:
            name = "sem nome"
        return f"{char!r}  U+{ord(char):04X}  {name}"


class Runner:
    def __init__(self):
        self.failures = []

    def guided(self):
        print(f"{Palette.YELLOW}Roteiro ABNT2 -- {len(Roteiro.ITEMS)} caracteres.{Palette.OFF}")
        print(f"{Palette.DIM}Enter pula um item, Esc encerra e mostra o resumo.{Palette.OFF}\n")

        for index, item in enumerate(Roteiro.ITEMS, start=1):
            prefix = f"[{index:2d}/{len(Roteiro.ITEMS)}]"
            print(f"{prefix} digite:  {Palette.YELLOW}{item.char}{Palette.OFF}"
                  f"   {Palette.DIM}({item.where}){Palette.OFF}")
            got = Reader.one_char()

            if got == "\x1b":
                print(f"\n{Palette.YELLOW}Encerrado.{Palette.OFF}")
                break
            if got in ("\r", "\n"):
                print(f"       {Palette.DIM}pulado{Palette.OFF}\n")
                continue

            if got == item.char:
                print(f"       {Palette.GREEN}OK{Palette.OFF}\n")
            else:
                print(f"       {Palette.RED}veio{Palette.OFF} {Reader.describe(got)}\n")
                self.failures.append((item, got))

        self.report()

    def report(self):
        print("=" * 60)
        if not self.failures:
            print(f"{Palette.GREEN}Tudo certo -- nenhum caractere saiu errado.{Palette.OFF}")
            return
        print(f"{Palette.RED}{len(self.failures)} caractere(s) fora do esperado:{Palette.OFF}\n")
        for item, got in self.failures:
            print(f"  esperado {Palette.YELLOW}{item.char}{Palette.OFF}"
                  f"   veio {Reader.describe(got)}")
            print(f"  {Palette.DIM}deveria estar em: {item.where}{Palette.OFF}\n")
        print("Passe esta lista para eu corrigir os bindings.")

    def free(self):
        print(f"{Palette.YELLOW}Modo livre -- cada tecla mostra o que chegou.{Palette.OFF}")
        print(f"{Palette.DIM}Esc encerra.{Palette.OFF}\n")
        while True:
            got = Reader.one_char()
            if got == "\x1b":
                print(f"\n{Palette.YELLOW}Encerrado.{Palette.OFF}")
                return
            print(f"  {Reader.describe(got)}")


class Main:
    @staticmethod
    def run():
        runner = Runner()
        if "--livre" in sys.argv:
            runner.free()
        else:
            runner.guided()


if __name__ == "__main__":
    try:
        Main.run()
    except KeyboardInterrupt:
        print("\ninterrompido")
