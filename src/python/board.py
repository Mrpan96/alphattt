# -*- coding: UTF-8 -*-


class Board(object):

    PLAYER_ME = 0
    PLAYER_AI = 1
    PLAYER_NO = 2
    BOARDS = (1, 2, 4, 8, 16, 32, 64, 128, 256)
    RS = (0, 0, 0, 1, 1, 1, 2, 2, 2)
    CS = (0, 1, 2, 0, 1, 2, 0, 1, 2)
    WINS = (7, 56, 448, 73, 146, 292, 273, 84)
    MAX_BOARD = 511
    POINTS = ((0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2))
    RC2S = {(0, 0): 0, (0, 1): 1, (0, 2): 2,
            (1, 0): 3, (1, 1): 4, (1, 2): 5,
            (2, 0): 6, (2, 1): 7, (2, 2): 8}

    def __init__(self, copy_board=None):
        super(Board, self).__init__()
        self.board = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                      0, 0, 2, 0, 0]
        self.legals = [511 for i in xrange(9)]
        self.overs = [0 for i in xrange(9)]

    def __is_win(self, n):
        for i in Board.WINS:
            if (n & i) == i:
                return True
        return False

    def is_legal(self, (R, C, r, c)):
        pass

    def winner(self):
        pass

    def max_moves(self):
        pass

    def current_player(self):
        pass

    def move(self, ((R, C, r, c), player)):
        s, n = Board.RC2S[(R, C)], Board.RC2S[(r, c)]
        S, N = Board.BOARDS[s], Board.BOARDS[n]
        ssp = s + s + player
        winner = None
        # move
        self.board[ssp] += N
        self.legals[s] -= N
        self.board[20], self.board[21], self.board[22] = player, s, n
        # calculate
        if self.__is_win(self.board[ssp]):
            self.board[18 + player] += S
            self.overs[s] = 1
            if self.__is_win(self.board[18 + player]):
                winner = player
        elif not self.legals[s]:
            self.overs[s] = 1
        if sum(self.overs) == 9 \
                and winner is None:
            winner = Board.PLAYER_NO
        return winner

    def legal_moves(self):
        def append_points(legal_moves, m, s):
            R, C = Board.RS[s], Board.CS[s]
            for i in xrange(9):
                if (m | Board.BOARDS[i]) == m:
                    legal_moves.append((R, C, Board.RS[i], Board.CS[i]))
        legal_moves = []
        n = self.board[22]
        if self.overs[n]:
            for index in xrange(9):
                if not self.overs[index]:
                    append_points(legal_moves, self.legals[index], index)
        else:
            append_points(legal_moves, self.legals[n], n)
        return legal_moves

    def get_board(self):
        return tuple(self.board)

    def display(self):
        line = [["0" for i in xrange(9)] for i in xrange(9)]
        for N in xrange(9):
            I = self.board[N * 2]
            A = self.board[N * 2 + 1]
            for n in xrange(9):
                if ((I >> n) & 1) == 1:
                    line[int(N / 3) * 3 + int(n / 3)][(N % 3) * 3 + n % 3] = "I"
                if ((A >> n) & 1) == 1:
                    line[int(N / 3) * 3 + int(n / 3)][(N % 3) * 3 + n % 3] = "A"
        for i in xrange(9):
            for j in xrange(9):
                if j == 8:
                    print line[i][j] + " "
                else:
                    print line[i][j] + " ",
                    if (j + 1) % 3 == 0:
                        print " ",
            if (i + 1) % 3 == 0:
                print "---"
