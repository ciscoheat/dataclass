package subpack;

import Tests;

class TreeChapter implements ITreeNode {
    public var id : String = 'Chapter id';
    public var children : Array<ITreeNode> = [];
    
    public var chapterSpecific: Int = 1;
}
