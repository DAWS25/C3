package ay.classifier;

import ay.model.*;

public interface Classifier {
    Ranking rank(Cell cell);
}